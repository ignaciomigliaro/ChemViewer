import AppKit
import ChemCraftCore
import SwiftUI

struct EnergyPlotRequest: Encodable, Sendable {
    struct PlotAtom: Encodable, Sendable { let element: String; let x: Float; let y: Float; let z: Float }
    struct Point: Encodable, Sendable {
        let geometry: Int
        let x: Double
        let energyHartree: Double?
        let energyKind: String
        let comment: String
        let atoms: [PlotAtom]
        var label: String? = nil
        var relativeEnergyKcal: Double? = nil
        var sourceLine: Int? = nil
        var structureSource: String? = nil
    }
    let title: String
    let unit: String
    let reference: String
    let xKind: String
    let xLabel: String
    let structures: Bool
    let connect: Bool
    let annotate: Bool
    let widthInches: Double
    let dpi: Int
    let points: [Point]
    var markers = true
    var plotStyle = "profile"
    var dataSource = "optimization"
    var tsIndex: Int? = nil
    var status: String? = nil
}

struct EnergyPlotOptions: Equatable {
    var title = "Energy profile"
    var unit: EnergyUnit = .kilojoulePerMole
    var reference = "minimum"
    var coordinate = "index"
    var kind = "final"
    var structures = true
    var connect = true
    var annotate = true
    var widthInches = 6.8
    var neb = false
    var nebContent = "states"
    var markers = true
    var plotStyle = "profile"

    static func initial(for document: ParsedDocument?) -> EnergyPlotOptions {
        var options = EnergyPlotOptions()
        if let profile = document?.nebProfile {
            options.neb = true; options.plotStyle = "diagram"; options.reference = "first"; options.unit = .kilocaloriePerMole; options.markers = false
            options.title = profile.isNEBTS ? "NEB-TS reaction profile" : "NEB reaction profile"
            if profile.transitionState == nil { options.nebContent = "images" }
        }
        return options
    }

    @MainActor func request(workspace: WorkspaceStore) throws -> EnergyPlotRequest {
        func failure(_ text: String) -> NSError { NSError(domain: "EnergyPlot", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
        guard let document = workspace.document else { throw failure("Open a calculation or multi-XYZ first.") }
        if neb {
            guard let profile = document.nebProfile else { throw failure("No complete NEB path summary was found in this output.") }
            let selected: [NEBImage]
            if nebContent == "states" {
                guard let ts = profile.transitionState else { throw failure("No refined TS is present. Choose All NEB images instead.") }
                selected = [profile.reactant, ts, profile.product]
            } else { selected = profile.images }
            let points = selected.enumerated().map { index, image -> EnergyPlotRequest.Point in
                let label = image.isTransitionState ? "Transition state" : image.imageIndex == 0 ? "Reactants" : image.imageIndex == profile.product.imageIndex ? "Products" : "Image \(image.name)\(image.isClimbingImage ? " (CI)" : "")"
                return .init(geometry: index + 1, x: Double(index), energyHartree: image.energyHartree, energyKind: "NEB summary electronic energy", comment: "ORCA path summary; printed relative energy in kcal/mol", atoms: image.atoms.map { .init(element: $0.element, x: $0.position.x, y: $0.position.y, z: $0.position.z) }, label: label, relativeEnergyKcal: image.relativeKcal, sourceLine: image.sourceLine, structureSource: image.structureSource)
            }
            return EnergyPlotRequest(title: title, unit: unit.rawValue, reference: reference, xKind: "neb", xLabel: "Reaction coordinate (schematic path order)", structures: structures, connect: connect, annotate: annotate, widthInches: widthInches, dpi: 600, points: points, markers: markers, plotStyle: plotStyle, dataSource: "ORCA NEB path summary", tsIndex: selected.firstIndex(where: \.isTransitionState), status: profile.tsConverged ? "Refined TS optimization converged" : profile.isNEBTS ? "TS convergence not confirmed in this summary" : "NEB path summary without a refined TS row")
        }
        let indices = workspace.selectedAtomIndices
        if coordinate == "distance" && indices.count != 2 { throw failure("Select two atoms, then choose Selected distance.") }
        if coordinate == "angle" && indices.count != 3 { throw failure("Select three atoms in A–B–C order, then choose Selected angle.") }
        let referenceAtoms = workspace.currentFrame?.atoms ?? []
        let points = try document.frames.enumerated().map { index, frame -> EnergyPlotRequest.Point in
            var x = Double(index + 1)
            if coordinate != "index" {
                guard indices.allSatisfy({ frame.atoms.indices.contains($0) && referenceAtoms.indices.contains($0) && frame.atoms[$0].element == referenceAtoms[$0].element }) else { throw failure("The selected atom identities are inconsistent across geometries.") }
                if coordinate == "distance" { x = Double(try GeometryEditor.distance(in: frame, firstAtomIndex: indices[0], secondAtomIndex: indices[1])) }
                else { x = Double(try GeometryEditor.angleDegrees(in: frame, firstAtomIndex: indices[0], vertexAtomIndex: indices[1], thirdAtomIndex: indices[2])) }
            }
            let records = document.energyRecords.filter { $0.frameIndex == index }
            let scf = records.last { $0.kind == .scf }
            let energy = workspace.isFrameEdited(index) ? nil : kind == "scf" ? scf?.hartree() : frame.energyHartree
            let label = kind == "scf" ? EnergyKind.scf.rawValue : (records.last { $0.kind == .singlePoint } ?? records.last)?.kind.rawValue ?? "Energy"
            return EnergyPlotRequest.Point(geometry: index + 1, x: x, energyHartree: energy, energyKind: label, comment: frame.comment,
                atoms: frame.atoms.map { .init(element: $0.element, x: $0.position.x, y: $0.position.y, z: $0.position.z) })
        }
        guard points.filter({ $0.energyHartree != nil }).count >= 2 else { throw failure("At least two geometries need energies. For unitless XYZ comments, choose the input unit in Abstract first. Edited geometries need recalculated energies or Undo.") }
        let label = coordinate == "distance" ? "Distance (Å)" : coordinate == "angle" ? "Angle (°)" : "Geometry index"
        return EnergyPlotRequest(title: title, unit: unit.rawValue, reference: reference, xKind: coordinate, xLabel: label,
            structures: structures, connect: connect, annotate: annotate, widthInches: widthInches, dpi: 600, points: points, markers: markers, plotStyle: plotStyle)
    }
}

enum MatplotlibRunner {
    static func render(_ request: EnergyPlotRequest) async throws -> URL {
        try await Task.detached(priority: .userInitiated) { try renderBlocking(request) }.value
    }
    private static func renderBlocking(_ request: EnergyPlotRequest) throws -> URL {
            let fm = FileManager.default
            let support = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ChemViewer")
            let python = ProcessInfo.processInfo.environment["CHEMVIEWER_PYTHON"].map { URL(fileURLWithPath: $0) }
                ?? support.appendingPathComponent("plotting-venv/bin/python3")
            guard fm.isExecutableFile(atPath: python.path) else {
                throw NSError(domain: "Matplotlib", code: 1, userInfo: [NSLocalizedDescriptionKey: "Matplotlib is not configured. Run bash scripts/setup-plotting.sh from the ChemViewer project, then reopen this plot."])
            }
            let resourceBundle = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("ChemViewer_ChemViewerApp.bundle")) } ?? .module
            guard let script = resourceBundle.url(forResource: "energy_landscape", withExtension: "py") else { throw CocoaError(.fileNoSuchFile) }
            let directory = fm.temporaryDirectory.appendingPathComponent("ChemViewer-energy-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            do {
                let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let input = directory.appendingPathComponent("plot-input.json")
                try encoder.encode(request).write(to: input)
                let log = directory.appendingPathComponent("matplotlib.log")
                fm.createFile(atPath: log.path, contents: nil)
                let stream = try FileHandle(forWritingTo: log)
                defer { try? stream.close() }
                let process = Process(); process.executableURL = python; process.arguments = [script.path, input.path, directory.path]
                var environment = ProcessInfo.processInfo.environment
                environment["MPLBACKEND"] = "Agg"
                environment["MPLCONFIGDIR"] = support.appendingPathComponent("matplotlib-cache").path
                process.environment = environment
                process.standardOutput = stream; process.standardError = stream
                let finished = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in finished.signal() }
                try process.run()
                if finished.wait(timeout: .now() + 90) == .timedOut {
                    process.terminate()
                    _ = finished.wait(timeout: .now() + 5)
                    throw NSError(domain: "Matplotlib", code: 2, userInfo: [NSLocalizedDescriptionKey: "Matplotlib exceeded the 90-second plotting limit."])
                }
                guard process.terminationStatus == 0 else {
                    let details = (try? String(contentsOf: log)) ?? "Unknown plotting error"
                    throw NSError(domain: "Matplotlib", code: 3, userInfo: [NSLocalizedDescriptionKey: String(details.suffix(4000))])
                }
                try fm.copyItem(at: script, to: directory.appendingPathComponent("energy_landscape.py"))
                return directory
            } catch { try? fm.removeItem(at: directory); throw error }
    }
}

struct EnergyLandscapeView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @State private var options = EnergyPlotOptions()
    @State private var image: NSImage?
    @State private var directory: URL?
    @State private var busy = false
    @State private var needsUpdate = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Energy landscape").font(.title2.bold())
            if let profile = workspace.document?.nebProfile {
                Toggle("NEB reaction profile (reactants → TS → products)", isOn: $options.neb)
                if options.neb {
                    HStack {
                        Picker("Content", selection: $options.nebContent) { Text("Reactants / TS / products").tag("states"); Text("All NEB images + refined TS").tag("images") }
                        Button("Source summary") { workspace.isEnergyLandscapePresented = false; workspace.showSource(line: profile.sourceLine) }
                    }
                    if let forward = profile.forwardBarrierKcal, let reverse = profile.reverseBarrierKcal {
                        let factor = options.unit.perHartree / EnergyUnit.kilocaloriePerMole.perHartree
                        Text("Forward ΔE‡: \(forward * factor, specifier: "%.2f") · Reverse ΔE‡: \(reverse * factor, specifier: "%.2f") · Reaction ΔE: \(profile.reactionEnergyKcal * factor, specifier: "%.2f") \(options.unit.rawValue)")
                            .font(.caption.monospaced()).textSelection(.enabled)
                    }
                    if profile.isNEBTS && !profile.tsConverged { Text("TS convergence was not confirmed for this summary.").font(.caption).foregroundStyle(.orange) }
                    Text("Electronic energies, not ΔG. Barriers use the printed refined TS row, not the highest climbing image. Full-band images may be higher than the refined TS.").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                TextField("Figure title", text: $options.title).textFieldStyle(.roundedBorder)
                Picker("Energy", selection: $options.kind) { Text("Final / XYZ comment").tag("final"); Text("SCF").tag("scf") }.frame(width: 235).disabled(options.neb)
            }
            HStack {
                Picker("Y unit", selection: $options.unit) { ForEach(EnergyUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("Zero", selection: $options.reference) { Text("Minimum").tag("minimum"); Text("First available").tag("first"); Text("Absolute").tag("absolute") }
                Picker("X axis", selection: $options.coordinate) { Text("Geometry index").tag("index"); Text("Selected distance").tag("distance"); Text("Selected angle").tag("angle") }.disabled(options.neb)
            }
            HStack {
                Toggle("Structures", isOn: $options.structures)
                Toggle("Connect points", isOn: $options.connect)
                Toggle("Markers", isOn: $options.markers)
                Toggle(options.plotStyle == "diagram" ? "Energy labels" : "Point labels", isOn: $options.annotate)
                Picker("Width", selection: $options.widthInches) { Text("Single column").tag(3.5); Text("Double column").tag(6.8) }.frame(width: 220)
            }
            Picker("Plot style", selection: $options.plotStyle) { Text("PES / line profile").tag("profile"); Text("Reaction diagram (levels + dashed connections)").tag("diagram") }
            ZStack {
                Color.white
                if let image { Image(nsImage: image).resizable().interpolation(.high).scaledToFit() }
                if busy { ProgressView("Rendering with Matplotlib…").padding().background(.regularMaterial) }
            }.frame(minHeight: 370).border(Color.gray.opacity(0.25))
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Text(options.neb ? "NEB data come from the last path summary, independently of the TS optimization history. Structure thumbnails appear only when matching companion XYZ files are available. Exports: PDF, SVG, 600-dpi PNG, CSV and source data." : "Geometries follow file order. Export includes vector PDF/SVG, 600-dpi PNG, CSV, source data and the plotting script.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Close") { dismiss() }
                Spacer()
                Button(needsUpdate ? "Update plot" : "Render again") { Task { await generate() } }.disabled(busy)
                Button("Export figure and data…") { export() }.disabled(busy || needsUpdate || directory == nil)
            }
        }.padding(18).frame(minWidth: 820, idealWidth: 950, minHeight: 620)
        .task {
            options = .initial(for: workspace.document)
            await generate()
        }
        .onChange(of: options.neb) { enabled in options.plotStyle = enabled ? "diagram" : "profile" }
        .onChange(of: options) { _ in needsUpdate = true }
        .onDisappear { if let directory { try? FileManager.default.removeItem(at: directory) } }
    }
    private func generate() async {
        busy = true; errorMessage = nil
        defer { busy = false }
        do {
            let renderedOptions = options
            let request = try renderedOptions.request(workspace: workspace)
            let output = try await MatplotlibRunner.render(request)
            guard !Task.isCancelled else { try? FileManager.default.removeItem(at: output); return }
            if let directory { try? FileManager.default.removeItem(at: directory) }
            directory = output
            image = NSImage(contentsOf: output.appendingPathComponent("energy-profile.png"))
            needsUpdate = options != renderedOptions
        } catch { errorMessage = error.localizedDescription }
    }
    private func export() {
        guard let directory else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.prompt = "Export here"
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        do {
            let output = parent.appendingPathComponent("Energy-profile-\(String(UUID().uuidString.prefix(8)))", isDirectory: true)
            try FileManager.default.copyItem(at: directory, to: output)
            NSWorkspace.shared.activateFileViewerSelecting([output.appendingPathComponent("energy-profile.pdf")])
        } catch { errorMessage = error.localizedDescription }
    }
}
