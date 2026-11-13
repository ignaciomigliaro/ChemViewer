import ChemCraftCore
import SwiftUI

struct SelectionInspector: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var target: Float = 1
    @State private var angleMovement: GeometryEditor.AngleMovement = .thirdFragment
    @State private var movement: GeometryEditor.DistanceMovement = .secondFragment
    private var indices: [Int] { workspace.selectedAtomIndices }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Selection (\(indices.count))").font(.headline)
                Spacer()
                if (2...4).contains(indices.count) {
                    Toggle(indices.count == 2 ? "Show bond length" : indices.count == 3 ? "Show angle" : "Show dihedral", isOn: Binding(get: { workspace.isSelectionMeasurementVisible }, set: workspace.setSelectionMeasurementVisible))
                        .toggleStyle(.checkbox)
                    if workspace.isSelectionMeasurementVisible {
                        Button("Reset label") { NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "resetLabel") }
                            .help("Drag the measurement label in the canvas to reposition it.")
                    }
                }
                GeometryEditButton(title: "Generate bonds", id: "geometry-generate-bonds") { workspace.generateBonds() }.frame(width: 105, height: 24)
                Button("Select all") { workspace.selectedAtomIndices = Array(workspace.currentFrame?.atoms.indices ?? 0..<0) }
                Button("Clear") { workspace.clearSelection() }.disabled(indices.isEmpty)
            }
            if !workspace.pinnedMeasurementSelections.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        Text("Visible labels:").font(.caption)
                        ForEach(workspace.pinnedMeasurementSelections, id: \.self) { selection in
                            HStack(spacing: 3) {
                                Button(selection.map { String($0 + 1) }.joined(separator: "–")) { workspace.selectedAtomIndices = selection }
                                Button { workspace.removeMeasurement(selection) } label: { Image(systemName: "xmark.circle.fill") }.help("Remove this label")
                            }
                        }
                        Button("Hide all") { workspace.clearMeasurements() }
                    }
                }
            }
            if indices.isEmpty {
                Text("Click atoms to select them. Select 2 for a bond length, 3 for an angle, or 4 for a dihedral. Right-click clears the selection.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let frame = workspace.currentFrame {
                ScrollView(.horizontal) {
                    Text(indices.enumerated().filter { frame.atoms.indices.contains($0.element) }.map { "\($0.offset + 1): \(frame.atoms[$0.element].element)\($0.element + 1)" }.joined(separator: "  →  "))
                        .font(.caption.monospaced()).textSelection(.enabled)
                }
                if indices.count == 2 {
                    HStack {
                        Text("Distance (Å)")
                        TextField("Distance", value: $target, format: .number.precision(.fractionLength(6)))
                            .frame(width: 105).textFieldStyle(.roundedBorder)
                        Picker("Move", selection: $movement) {
                            ForEach([GeometryEditor.DistanceMovement.secondFragment, .bothFragments], id: \.self) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(width: 230)
                        GeometryEditButton(title: "Apply distance", id: "geometry-apply-distance") { workspace.applyDistance(target, movement: movement) }.frame(width: 110, height: 24)
                        GeometryEditButton(title: frame.bonds.contains { Set([$0.first, $0.second]) == Set(indices) } ? "Remove bond" : "Create bond", id: "geometry-toggle-bond") { workspace.toggleSelectedBond() }.frame(width: 100, height: 24)
                    }
                    Text("The entire second-side fragment moves rigidly. Both moves the two fragments equally. Rings cannot be split.").font(.caption).foregroundStyle(.secondary)
                } else if indices.count == 3 {
                    HStack {
                        Text("Angle (°)")
                        TextField("Angle", value: $target, format: .number.precision(.fractionLength(4)))
                            .frame(width: 105).textFieldStyle(.roundedBorder)
                        Picker("Angle movement", selection: $angleMovement) {
                            ForEach([GeometryEditor.AngleMovement.thirdFragment, .bothFragments], id: \.self) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().frame(width: 230)
                        GeometryEditButton(title: "Apply angle", id: "geometry-apply-angle") { workspace.applyAngle(target, movement: angleMovement) }.frame(width: 110, height: 24)
                    }
                    Text("B (selection 2) stays fixed. The C-side fragment, or both A/C fragments, rotate rigidly; internal lengths stay fixed.").font(.caption).foregroundStyle(.secondary)
                } else if indices.count == 4 {
                    if let value = try? GeometryEditor.dihedralDegrees(in: frame, firstAtomIndex: indices[0], secondAtomIndex: indices[1], thirdAtomIndex: indices[2], fourthAtomIndex: indices[3]) {
                        HStack {
                            Text("Dihedral: \(value, specifier: "%.3f")°").monospacedDigit()
                            Button("Copy value") { _ = ClipboardSupport.copy(String(format: "%.6f", Double(value))) }
                        }
                    } else { Text("Dihedral undefined for this selection.").font(.caption).foregroundStyle(.secondary) }
                } else if indices.count > 4 {
                    Text("Select two, three or four atoms for distance, angle or dihedral.").font(.caption).foregroundStyle(.secondary)
                }
                if workspace.selectedMode != nil { Text("Editor values use stored geometry; the overlay follows displayed atoms.").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(10).background(Color(nsColor: .controlBackgroundColor))
        .onAppear { refresh() }
        .onChange(of: indices) { _ in refresh() }
        .onChange(of: workspace.geometryRevision) { _ in refresh() }
    }
    private func refresh() {
        guard let frame = workspace.currentFrame else { return }
        if indices.count == 2 {
            target = (try? GeometryEditor.distance(in: frame, firstAtomIndex: indices[0], secondAtomIndex: indices[1])) ?? 1
        } else if indices.count == 3 {
            target = (try? GeometryEditor.angleDegrees(in: frame, firstAtomIndex: indices[0], vertexAtomIndex: indices[1], thirdAtomIndex: indices[2])) ?? 90
        }
    }
}
