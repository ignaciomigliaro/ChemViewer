import AppKit
import ChemCraftCore
import MetalKit
import simd
import SwiftUI
import UniformTypeIdentifiers

enum AnimationExportError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum AnimationSource: String, CaseIterable {
    case trajectory = "Geometry trajectory"
    case frequency = "Selected frequency"
    case rotation = "Rotate current geometry"

    var filename: String {
        switch self {
        case .trajectory: return "trajectory.gif"
        case .frequency: return "frequency.gif"
        case .rotation: return "rotation.gif"
        }
    }
}

enum GIFRotationAxis: String, CaseIterable {
    case x = "X", y = "Y", z = "Z"

    var vector: SIMD3<Float> {
        switch self {
        case .x: return SIMD3(1, 0, 0)
        case .y: return SIMD3(0, 1, 0)
        case .z: return SIMD3(0, 0, 1)
        }
    }
}

struct MolecularAnimation {
    let frames: [MoleculeFrame]
    let mode: VibrationalMode?
    let amplitude: Float
    let samples: Int
    let pingPong: Bool
    var rotationAxis: GIFRotationAxis? = nil

    var count: Int {
        if mode != nil || rotationAxis != nil { return samples }
        return frames.count + (pingPong ? max(0, frames.count - 2) : 0)
    }

    func rotation(at index: Int) -> simd_quatf? {
        rotationAxis.map { simd_quatf(angle: 2 * .pi * Float(index) / Float(samples), axis: $0.vector) }
    }
    func sample(_ index: Int) -> (MoleculeFrame, [SIMD3<Float>]) {
        let frameIndex = mode == nil && rotationAxis == nil ? (index < frames.count ? index : 2 * frames.count - 2 - index) : 0
        let frame = frames[frameIndex]
        let phase = mode == nil ? Float(0) : sin(Float(index) * 2 * .pi / Float(samples))
        let positions = frame.atoms.enumerated().map { i, atom -> SIMD3<Float> in
            var p = SIMD3(atom.position.x, atom.position.y, atom.position.z)
            if let mode, mode.displacements.indices.contains(i) {
                let d = mode.displacements[i]; p += SIMD3(d.x, d.y, d.z) * amplitude * phase
            }
            return p
        }
        return (frame, positions)
    }
}

@MainActor enum AnimationExporter {
    static let sizes = [256, 512, 640, 800, 1024, 1536, 2048]

    static func viewport() -> MolecularMTKView? {
        func find(_ view: NSView) -> MolecularMTKView? {
            if let molecular = view as? MolecularMTKView, !molecular.isHiddenOrHasHiddenAncestor, molecular.window != nil { return molecular }
            return view.subviews.compactMap(find).first
        }
        let active = NSApp.keyWindow?.sheetParent ?? NSApp.mainWindow ?? NSApp.keyWindow
        if let view = active?.contentView.flatMap(find) { return view }
        return NSApp.windows.filter { $0.sheetParent == nil && $0.isVisible }.compactMap { $0.contentView.flatMap(find) }.first
    }

    static func export(_ animation: MolecularAnimation, from viewport: MolecularMTKView, style: MolecularStyle, size: Int, fps: Double, to url: URL, playbackSpeed: Double = 1, measurementIndices: [Int] = [], measurementSelections: [[Int]] = [], transparentBackground: Bool = true, progress: (Double) -> Void) async throws {
        guard !animation.frames.isEmpty, animation.count >= 2, animation.count <= 2000,
              sizes.contains(size), fps >= 1, fps <= 50, playbackSpeed >= 0.125, playbackSpeed <= 1,
              animation.frames.allSatisfy({ !$0.atoms.isEmpty }),
              animation.rotationAxis == nil || (animation.frames.count == 1 && animation.mode == nil),
              animation.mode == nil || animation.mode?.displacements.count == animation.frames[0].atoms.count else {
            throw AnimationExportError.message("Choose a valid animation source and output settings (2–2,000 GIF frames).")
        }
        for indices in measurementSelections + (measurementIndices.isEmpty ? [] : [measurementIndices]) {
            guard (2...4).contains(indices.count), Set(indices).count == indices.count,
                  animation.frames.allSatisfy({ frame in indices.allSatisfy(frame.atoms.indices.contains) }),
                  animation.frames.allSatisfy({ $0.atoms.map(\.element) == animation.frames[0].atoms.map(\.element) }) else {
                throw AnimationExportError.message("Labels require 2, 3 or 4 distinct selected atoms and consistent atom ordering across geometries.")
            }
        }
        let renderer = viewport.animationRenderer(frames: animation.frames, amplitude: animation.amplitude,
                                                  displacements: animation.mode?.displacements ?? [], style: style)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".ChemViewer-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let writer = try GIFWriter(url: temporary, count: animation.count)
        for index in 0..<animation.count {
            try Task.checkCancellation()
            renderer.animationRotation = animation.rotation(at: index)
            let sample = animation.sample(index)
            let image = try autoreleasepool { try renderer.renderAnimationFrame(sample.0, positions: sample.1, size: size, measurementIndices: measurementIndices, measurementSelections: measurementSelections, transparentBackground: transparentBackground) }
            try await writer.append(image, delay: 1 / (fps * playbackSpeed))
            progress(Double(index + 1) / Double(animation.count))
            // Let progress and cancellation events run between GPU submissions.
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        try Task.checkCancellation()
        try await writer.finish()
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: url) }
    }
}

struct AnimationExportView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var source: AnimationSource = .trajectory
    @State private var size = 1024
    @State private var style = MolecularStyle.paton
    @State private var rotationAxis = GIFRotationAxis.y
    @State private var fps = 12.0
    @State private var playbackSpeed = 0.5
    @State private var includeMeasurement = false
    @State private var transparentBackground = true
    @State private var samples = 48
    @State private var pingPong = false
    @State private var progress: Double?
    @State private var task: Task<Void, Never>?
    @State private var result: String?
    @State private var failure: String?
    @State private var viewport: MolecularMTKView?
    private var available: Bool {
        switch source {
        case .trajectory: return (2...2000).contains(frameCount)
        case .frequency:
            guard let frame = workspace.currentFrame, let mode = workspace.selectedMode else { return false }
            return !frame.atoms.isEmpty && mode.displacements.count == frame.atoms.count
        case .rotation: return workspace.currentFrame?.atoms.isEmpty == false
        }
    }
    private var validSelection: Bool { (2...4).contains(workspace.selectedAtomIndices.count) }
    private var exportLabels: [[Int]] {
        if !workspace.pinnedMeasurementSelections.isEmpty { return workspace.pinnedMeasurementSelections }
        return validSelection ? [workspace.selectedAtomIndices] : []
    }
    private var measurementDescription: String {
        if !workspace.pinnedMeasurementSelections.isEmpty { return "\(exportLabels.count) persistent measurement labels" }
        let kind = workspace.selectedAtomIndices.count == 2 ? "Bond length" : workspace.selectedAtomIndices.count == 3 ? "Angle" : "Dihedral"
        return kind + " · atoms " + workspace.selectedAtomIndices.map { String($0 + 1) }.joined(separator: " → ")
    }
    private var frameCount: Int {
        source != .trajectory ? samples : (workspace.document?.frames.count ?? 0) + (pingPong ? max(0, (workspace.document?.frames.count ?? 0) - 2) : 0)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export animated GIF").font(.title2)
            Picker("Animate", selection: $source) {
                ForEach(AnimationSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            if source == .trajectory {
                Text("\(workspace.document?.frames.count ?? 0) geometries, in file order. Coordinates are preserved without interpolation.").font(.callout)
                Toggle("Play forward and backward", isOn: $pingPong)
            } else if source == .frequency {
                if let mode = workspace.selectedMode, available {
                    Text("Mode \(mode.index) · \(mode.frequencyCM1, specifier: "%.2f") cm⁻¹")
                    Stepper("Frames per cycle: \(samples)", value: $samples, in: 12...120, step: 12)
                    Text("Uses the viewer’s amplitude (\(workspace.vibrationAmplitude, specifier: "%.2f")). Playback speed is illustrative, not physical time.").font(.callout)
                } else { Text("Select a frequency with normal-mode vectors in the explorer first.").foregroundStyle(.secondary) }
            } else {
                Picker("Molecular axis", selection: $rotationAxis) {
                    ForEach(GIFRotationAxis.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Stepper("Frames per turn: \(samples)", value: $samples, in: 12...120, step: 12)
            }
            Picker("Appearance", selection: $style) {
                ForEach(MolecularStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            HStack {
                Picker("Resolution (px)", selection: $size) { ForEach(AnimationExporter.sizes, id: \.self) { Text("\($0) × \($0)").tag($0) } }
                Picker("Frames/s", selection: $fps) { ForEach([1.0, 2, 5, 10, 12, 20, 25, 30], id: \.self) { Text(String(Int($0))).tag($0) } }
            }
            Picker("Playback speed", selection: $playbackSpeed) {
                Text("Normal (1×)").tag(1.0)
                Text("Half speed (0.5×)").tag(0.5)
                Text("Quarter speed (0.25×)").tag(0.25)
                Text("Eighth speed (0.125×)").tag(0.125)
            }.disabled(task != nil)
            Text("Approximate loop: \(Double(frameCount) / (fps * playbackSpeed), specifier: "%.1f") seconds. Slower playback keeps every frame.").font(.caption)
            Toggle("Transparent background", isOn: $transparentBackground).disabled(task != nil)
            Text("GIF transparency has hard edges; it cannot retain partial opacity.").font(.caption).foregroundStyle(.secondary)
            Toggle("Include measurement label and guides", isOn: $includeMeasurement)
                .disabled(exportLabels.isEmpty || task != nil)
            if !exportLabels.isEmpty {
                Text(measurementDescription + ". Recomputed for every animation frame.").font(.caption)
            } else {
                Text("Before exporting, select 2 atoms for a length, 3 for an angle (middle atom is the vertex), or 4 for a signed dihedral, in order.").font(.caption).foregroundStyle(.secondary)
            }
            Text(source == .rotation
                 ? "Starts at the current viewing angle and loops through one full turn."
                 : "Fits all frames once at the current viewing angle and loops continuously.")
                .font(.caption).foregroundStyle(.secondary)
            if let progress { ProgressView(value: progress); Text("Rendering \(Int(progress * 100))%…").font(.caption) }
            if let result { Text(result).foregroundStyle(.green).textSelection(.enabled) }
            if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                if task != nil { Button("Cancel export") { task?.cancel() } }
                Spacer()
                Button("Close") { dismiss() }.disabled(task != nil)
                Button("Save GIF…", action: save).keyboardShortcut(.defaultAction).disabled(!available || task != nil || viewport == nil)
            }
        }
        .padding(24).frame(width: 540)
        .interactiveDismissDisabled(task != nil)
        .onAppear {
            viewport = AnimationExporter.viewport()
            style = workspace.renderingStyle
            if let mode = workspace.selectedMode, let frame = workspace.currentFrame,
               !frame.atoms.isEmpty, mode.displacements.count == frame.atoms.count {
                source = .frequency
            } else if (workspace.document?.frames.count ?? 0) < 2 {
                source = .rotation
            }
            includeMeasurement = !workspace.pinnedMeasurementSelections.isEmpty || (validSelection && workspace.showMeasurementOverlay)
        }
        .onDisappear { task?.cancel() }
    }
    private func save() {
        guard available, let viewport, let frame = workspace.currentFrame else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.gif]; panel.nameFieldStringValue = source.filename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let animation = MolecularAnimation(frames: source == .trajectory ? (workspace.document?.frames ?? []) : [frame], mode: source == .frequency ? workspace.selectedMode : nil, amplitude: workspace.vibrationAmplitude, samples: samples, pingPong: source == .trajectory && pingPong, rotationAxis: source == .rotation ? rotationAxis : nil)
        let style = self.style
        let size = self.size
        let fps = self.fps
        let labels = includeMeasurement ? exportLabels : []
        let speed = playbackSpeed
        let transparent = transparentBackground
        failure = nil; result = nil; progress = 0
        task = Task { @MainActor in
            defer { task = nil; progress = nil }
            do {
                try await AnimationExporter.export(animation, from: viewport, style: style, size: size, fps: fps, to: url, playbackSpeed: speed, measurementSelections: labels, transparentBackground: transparent) { progress = $0 }
                result = "Saved \(animation.count) frames to \(url.lastPathComponent)."
            } catch is CancellationError { result = "Export cancelled." }
            catch { failure = error.localizedDescription }
        }
    }
}
