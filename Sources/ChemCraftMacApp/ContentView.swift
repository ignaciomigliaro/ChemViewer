import ChemCraftCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 230, idealWidth: 270, maxWidth: 360)
            mainPanel
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    workspace.isImporterPresented = true
                } label: {
                    Label("Open", systemImage: "folder")
                }
                if workspace.selectedMode != nil {
                    Button {
                        workspace.isVibrating.toggle()
                    } label: {
                        Label(
                            workspace.isVibrating ? "Pause vibration" : "Animate vibration",
                            systemImage: workspace.isVibrating ? "pause.fill" : "play.fill"
                        )
                    }
                    Toggle(isOn: $workspace.showDisplacementVectors) {
                        Label("Mode vectors", systemImage: "arrow.up.right")
                    }
                }
                if workspace.document != nil {
                    Button {
                        workspace.isCoordinateEditorPresented = true
                    } label: {
                        Label("Coordinates", systemImage: "tablecells")
                    }
                    Button {
                        workspace.undoGeometry()
                    } label: {
                        Label("Undo geometry", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!workspace.canUndoGeometry)
                }
                if let document = workspace.document, document.frames.count > 1 {
                    Button {
                        workspace.toggleTrajectoryPlayback()
                    } label: {
                        Label(
                            workspace.isPlayingTrajectory ? "Pause trajectory" : "Play trajectory",
                            systemImage: workspace.isPlayingTrajectory ? "pause.fill" : "play.fill"
                        )
                    }
                }
                if let document = workspace.document,
                   document.vibrationalModes.contains(where: { $0.infraredIntensity != nil }) {
                    Button {
                        workspace.isSpectrumPresented = true
                    } label: {
                        Label("IR spectrum", systemImage: "chart.xyaxis.line")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $workspace.isImporterPresented,
            allowedContentTypes: [.plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { workspace.open(url) }
            case .failure(let error):
                workspace.errorMessage = error.localizedDescription
            }
        }
        .onOpenURL { url in
            workspace.open(url)
        }
        .alert("Could not open file", isPresented: Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } }
        )) {
            Button("OK") { workspace.errorMessage = nil }
        } message: {
            Text(workspace.errorMessage ?? "Unknown error")
        }
        .sheet(isPresented: $workspace.isSpectrumPresented) {
            if let modes = workspace.document?.vibrationalModes {
                SpectrumView(modes: modes)
                    .frame(minWidth: 760, minHeight: 480)
            }
        }
        .sheet(isPresented: $workspace.isCoordinateEditorPresented) {
            if let frame = workspace.currentFrame {
                CoordinateEditorView(frame: frame) { atoms in
                    workspace.replaceCurrentAtoms(atoms)
                }
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let document = workspace.document {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(2)
                    .padding()
                Divider()
                List {
                    Section("Geometries") {
                        ForEach(Array(document.frames.enumerated()), id: \.offset) { index, frame in
                            Button {
                                workspace.selectFrame(index)
                            } label: {
                                HStack {
                                    Image(systemName: workspace.frameIndex == index ? "circle.inset.filled" : "circle")
                                    Text("Geometry \(index + 1)")
                                    Spacer()
                                    if let energy = frame.energyHartree {
                                        Text(energy, format: .number.precision(.fractionLength(6)))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if !document.vibrationalModes.isEmpty {
                        Section("Frequencies (cm⁻¹)") {
                            ForEach(document.vibrationalModes) { mode in
                                Button {
                                    workspace.selectedModeIndex = mode.index
                                } label: {
                                    HStack {
                                        Image(systemName: workspace.selectedModeIndex == mode.index ? "waveform.circle.fill" : "waveform.circle")
                                        Text("Mode \(mode.index)")
                                        Spacer()
                                        Text(mode.frequencyCM1, format: .number.precision(.fractionLength(2)))
                                            .monospacedDigit()
                                            .foregroundStyle(mode.isImaginary ? Color.red : Color.primary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if !document.warnings.isEmpty {
                    Divider()
                    ForEach(document.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "atom")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("No calculation open")
                        .font(.headline)
                    Text("Open an XYZ or ORCA output file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
    }

    @ViewBuilder
    private var mainPanel: some View {
        if workspace.isLoading {
            ProgressView("Parsing calculation…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let document = workspace.document,
                  document.frames.indices.contains(workspace.frameIndex) {
            VStack(spacing: 0) {
                MoleculeMetalView(
                    frame: document.frames[workspace.frameIndex],
                    mode: workspace.selectedMode,
                    isAnimating: workspace.isVibrating,
                    amplitude: workspace.vibrationAmplitude,
                    showDisplacementVectors: workspace.showDisplacementVectors,
                    selectedAtomIndices: $workspace.selectedAtomIndices
                )
                Divider()
                statusBar(document)
            }
        } else {
            VStack(spacing: 16) {
                Image(systemName: "atom")
                    .font(.system(size: 72))
                    .foregroundStyle(.secondary)
                Text("ChemViewer")
                    .font(.largeTitle)
                Text("Native Apple Silicon molecular visualization prototype")
                    .foregroundStyle(.secondary)
                Button("Open chemistry file…") { workspace.isImporterPresented = true }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func statusBar(_ document: ParsedDocument) -> some View {
        HStack(spacing: 16) {
            Text(document.sourceFormat)
            Text("Frame \(workspace.frameIndex + 1)/\(document.frames.count)")
            Text("\(document.frames[workspace.frameIndex].atoms.count) atoms")
            if !workspace.selectedAtomIndices.isEmpty {
                Divider().frame(height: 18)
                Text(selectionSummary(for: document.frames[workspace.frameIndex]))
                    .monospacedDigit()
            }
            if let mode = workspace.selectedMode {
                Divider().frame(height: 18)
                Text("Mode \(mode.index): \(mode.frequencyCM1, specifier: "%.2f") cm⁻¹")
                    .foregroundStyle(mode.isImaginary ? Color.red : Color.primary)
                Toggle("Animate", isOn: $workspace.isVibrating)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Slider(value: $workspace.vibrationAmplitude, in: 0.05...2.0) {
                    Text("Amplitude")
                }
                .frame(width: 140)
            }
            Spacer()
            Text("Drag or right-drag to rotate • Option-drag to pan • scroll to zoom")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func selectionSummary(for frame: MoleculeFrame) -> String {
        let indices = workspace.selectedAtomIndices.filter(frame.atoms.indices.contains)
        let atoms = indices.map { "\(frame.atoms[$0].element)\($0 + 1)" }.joined(separator: ", ")
        do {
            switch indices.count {
            case 2:
                let value = try GeometryEditor.distance(
                    in: frame, firstAtomIndex: indices[0], secondAtomIndex: indices[1]
                )
                return "\(atoms)  d = \(value.formatted(.number.precision(.fractionLength(5)))) Å"
            case 3:
                let value = try GeometryEditor.angleDegrees(
                    in: frame,
                    firstAtomIndex: indices[0],
                    vertexAtomIndex: indices[1],
                    thirdAtomIndex: indices[2]
                )
                return "\(atoms)  angle = \(value.formatted(.number.precision(.fractionLength(3))))°"
            case 4:
                let value = try GeometryEditor.dihedralDegrees(
                    in: frame,
                    firstAtomIndex: indices[0],
                    secondAtomIndex: indices[1],
                    thirdAtomIndex: indices[2],
                    fourthAtomIndex: indices[3]
                )
                return "\(atoms)  dihedral = \(value.formatted(.number.precision(.fractionLength(3))))°"
            default:
                return "\(indices.count) selected: \(atoms)"
            }
        } catch {
            return "\(indices.count) selected: \(atoms)"
        }
    }
}
