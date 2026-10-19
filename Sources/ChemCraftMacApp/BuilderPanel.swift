import AppKit
import ChemCraftCore
import SwiftUI

struct BuilderPanel: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var fragmentIndex = 0
    @State private var imported: [Atom]?
    @State private var importedName = ""
    @State private var leaving = 1
    @State private var element = "C"
    @State private var selection = ""
    @State private var axis = "X"
    @State private var distance: Float = 0.1
    @State private var degrees: Float = 10
    private var fragment: [Atom] { imported ?? BuildingProject.fragment(fragmentIndex) }
    private var sites: [Int] { fragment.indices.filter { ["H", "X"].contains(fragment[$0].element) } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("BUILD & EDIT").font(.headline); Spacer(); Button { workspace.isBuilderVisible = false } label: { Image(systemName: "xmark") } }
                heading("CALCULATION & ANIMATION")
                if let document = workspace.document {
                    Picker("Geometry", selection: Binding(get: { workspace.frameIndex }, set: workspace.selectFrame)) {
                        ForEach(document.frames.indices, id: \.self) { Text("Geometry \($0 + 1)").tag($0) }
                    }
                }
                if !workspace.availableModes.isEmpty {
                    Picker("Mode cm⁻¹", selection: Binding(get: { workspace.selectedModeIndex ?? -1 }, set: workspace.selectMode)) {
                        Text("None").tag(-1)
                        ForEach(workspace.availableModes) { Text("\($0.index): \(String(format: "%.2f", $0.frequencyCM1))\($0.isImaginary ? " imaginary" : "")").tag($0.index) }
                    }
                }
                HStack { Button(workspace.isVibrating ? "Pause" : "Play frequency") { workspace.isVibrating.toggle() }.disabled(workspace.selectedMode == nil); Button("GIF…") { workspace.presentAnimationExport() } }
                HStack { Text("Amplitude"); Slider(value: $workspace.vibrationAmplitude, in: 0...2) }
                HStack { Text("Cycles/s"); Slider(value: $workspace.vibrationSpeed, in: 0.05...2); Text(workspace.vibrationSpeed, format: .number.precision(.fractionLength(2))).monospacedDigit() }
                heading("BUILD MOLECULE")
                Picker("Fragment", selection: $fragmentIndex) {
                    ForEach(Array(BuildingProject.fragmentNames.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) }
                }.onChange(of: fragmentIndex) { _ in imported = nil; resetSite() }
                if imported != nil { Text("Imported: \(importedName)").font(.caption) }
                HStack { Button("Add fragment") { workspace.addBuildingFragment(fragment) }; Button("Import XYZ…", action: importFragment) }
                Picker("Leaving site", selection: $leaving) {
                    ForEach(sites, id: \.self) { Text("\($0 + 1) \(fragment[$0].element)").tag($0) }
                }
                Button("Attach to selected H / X") { workspace.attachBuildingFragment(fragment, leaving: leaving) }.disabled(sites.isEmpty || workspace.selectedAtomIndices.count != 1)
                HStack { TextField("Element", text: $element).frame(width: 48); Button("Insert") { workspace.editElement(element, insert: true) }; Button("Replace") { workspace.editElement(element, insert: false) }.disabled(workspace.selectedAtomIndices.isEmpty) }
                heading("SELECT & EDIT")
                HStack { TextField("1,3-6", text: $selection).onSubmit { workspace.selectBuilderIndices(selection) }; Button("Select") { workspace.selectBuilderIndices(selection) } }
                HStack { Button("All") { workspace.selectedAtomIndices = Array(workspace.currentFrame?.atoms.indices ?? 0..<0) }; Button("Fragment") { workspace.selectImportedGroup() }; Button("Connected") { workspace.selectConnectedGroup() } }
                HStack { Button("Duplicate") { workspace.duplicateSelectedAtoms() }; Button("Delete") { workspace.deleteSelectedAtoms() } }.disabled(workspace.selectedAtomIndices.isEmpty)
                HStack { Button("Undo") { workspace.undoGeometry() }.disabled(!workspace.canUndoGeometry); Button("Redo") { workspace.redoGeometry() }.disabled(!workspace.canRedoGeometry) }
                heading("MOVE & ROTATE")
                Picker("Axis", selection: $axis) { ForEach(["X", "Y", "Z", "Bond"], id: \.self) { Text($0).tag($0) } }
                Picker("Pivot", selection: $workspace.rotationPivot) { ForEach(RotationPivot.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                HStack { Text("Move Å"); TextField("Distance", value: $distance, format: .number).frame(width: 60); Button("−") { transform(-distance, 0) }; Button("+") { transform(distance, 0) } }
                HStack { Text("Rotate °"); TextField("Degrees", value: $degrees, format: .number).frame(width: 60); Button("−") { transform(0, -degrees) }; Button("+") { transform(0, degrees) } }
                Button("Set bond axis from selected pair") { workspace.setBuildingBondAxis(); axis = "Bond" }
                heading("SAVE & EXPORT")
                HStack { Text("Charge"); TextField("Charge", value: $workspace.charge, format: .number).frame(width: 44); Text("Multiplicity"); TextField("Multiplicity", value: $workspace.multiplicity, format: .number).frame(width: 44) }
                HStack { Button("XYZ…") { workspace.requestXYZExport() }; Button("ORCA…") { workspace.exportORCAGeometry() }; Button("Project…") { workspace.saveBuildingProject() } }
                Text("Fragments are initial geometries; no energy minimization. Review charge and multiplicity before export. Projects save the working geometry, groups and selection; calculation outputs and normal modes stay in the original file.").font(.caption).foregroundStyle(.secondary)
            }.padding(14)
        }.frame(width: 310).background(Color(nsColor: .windowBackgroundColor)).controlSize(.small)
            .onAppear { resetSite(); selection = workspace.selectedAtomIndices.map { String($0 + 1) }.joined(separator: ",") }
            .onChange(of: workspace.selectedAtomIndices) { indices in selection = indices.map { String($0 + 1) }.joined(separator: ",") }
    }
    private func heading(_ text: String) -> some View { VStack(alignment: .leading) { Divider(); Text(text).font(.caption.bold()) } }
    private func resetSite() { leaving = sites.first ?? -1 }
    private func transform(_ distance: Float, _ degrees: Float) { workspace.transformBuildingSelection(axis: axis, distance: distance, degrees: degrees) }
    private func importFragment() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText, .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                let atoms = try await Task.detached {
                    let data = try Data(contentsOf: url)
                    guard data.count <= 10_000_000, let text = String(data: data, encoding: .utf8) else { throw ParseError.malformed("Fragment must be a UTF-8 XYZ file smaller than 10 MB.") }
                    guard let first = try XYZParser.parse(text: text).frames.first else { throw ParseError.noGeometry }
                    return first.atoms
                }.value
                imported = atoms; importedName = url.lastPathComponent; resetSite()
            } catch { workspace.errorMessage = error.localizedDescription }
        }
    }
}
