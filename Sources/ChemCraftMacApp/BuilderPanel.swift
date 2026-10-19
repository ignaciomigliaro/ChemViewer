import AppKit
import ChemCraftCore
import SwiftUI

struct BuilderPanel: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var chemistry = ChemistryRuntime.shared
    @State private var query = ""
    @State private var category = "All"
    @State private var freezeSelection = false
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
                HStack { Text("BUILD & EDIT").font(.headline); Spacer(); Button { workspace.isBuilderVisible = false; workspace.pendingAttachment = nil; workspace.pendingElement = nil; workspace.buildingHint = "" } label: { Image(systemName: "xmark") } }
                DisclosureGroup("Calculation & animation") {
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
                }
                fragmentControls
                chemistryControls
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
                Text("Fragments are initial geometries; use UFF cleanup where supported. Review charge and multiplicity before export. Projects save the working geometry, groups and selection; calculation outputs and normal modes stay in the original file.").font(.caption).foregroundStyle(.secondary)
            }.padding(14)
        }.frame(width: 310).background(Color(nsColor: .windowBackgroundColor)).controlSize(.small)
            .sheet(isPresented: $chemistry.showingWorkflow) { LocalWorkflowView() }
            .onChange(of: element) { value in if workspace.pendingElement != nil { workspace.pendingElement = value } }
            .onChange(of: leaving) { value in workspace.pendingAttachmentLeaving = value }
            .onAppear { resetSite(); selection = workspace.selectedAtomIndices.map { String($0 + 1) }.joined(separator: ",") }
            .onChange(of: workspace.selectedAtomIndices) { indices in selection = indices.map { String($0 + 1) }.joined(separator: ",") }
    }
    private var fragmentControls: some View {
        VStack(alignment: .leading, spacing: 8) {
                heading("BUILD MOLECULE")
                Picker("Fragment", selection: $fragmentIndex) {
                    ForEach(Array(BuildingProject.fragmentNames.enumerated()), id: \.offset) { Text($0.element).tag($0.offset) }
                }.onChange(of: fragmentIndex) { _ in imported = nil; workspace.pendingAttachment = nil; resetSite() }
                TextField("Search 258 fragments / metal centers", text: $query)
                Picker("Category", selection: $category) {
                    Text("All").tag("All")
                    ForEach(Array(Set(LibraryFragment.all.map(\.category))).sorted(), id: \.self) { Text($0).tag($0) }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(LibraryFragment.all.filter { (category == "All" || $0.category == category) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }) { item in
                            Button { chooseFragment(item) } label: {
                                HStack { Text(item.name); Spacer(); if importedName == item.name { Image(systemName: "checkmark") } }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain).padding(3)
                        }
                    }
                }.frame(height: 145).background(Color(nsColor: .textBackgroundColor))
                if imported != nil { Text("Fragment: \(importedName)").font(.caption) }
                HStack { Button("Use selected atoms") { useSelection() }; Button("Save fragment…") { saveFragment() } }.disabled(workspace.selectedAtomIndices.isEmpty)
                Button("My saved fragments…", action: loadSavedFragment)
                HStack { Button("Add fragment") { workspace.pendingAttachment = nil; workspace.pendingElement = nil; workspace.buildingHint = ""; workspace.addBuildingFragment(fragment) }; Button("Import XYZ…") { importFragment() } }
                Picker("Leaving site", selection: $leaving) {
                    ForEach(sites, id: \.self) { Text("\($0 + 1) \(fragment[$0].element)").tag($0) }
                }
                Button("Attach to selected atom") { workspace.attachBuildingFragment(fragment, leaving: leaving) }.disabled(sites.isEmpty || workspace.selectedAtomIndices.count != 1)
                Toggle("Click an atom to attach fragment", isOn: Binding(get: { workspace.pendingAttachment != nil }, set: { enabled in
                    workspace.pendingElement = nil; workspace.isDraggingEnabled = false
                    workspace.pendingAttachment = enabled ? fragment : nil; workspace.pendingAttachmentLeaving = leaving
                    workspace.buildingHint = enabled ? "Click H/X, or a heavy atom to use its available H/X site. Right-click finishes." : ""
                })).disabled(sites.isEmpty)
                Text("X marks a replaceable attachment site. Clicking a heavy atom uses its first H/X site, or adds a bond if none exist. Check valence, then clean up.").font(.caption).foregroundStyle(.secondary)
                Picker("Element", selection: $element) { ForEach(BuildingProject.elements, id: \.self) { Text($0).tag($0) } }
                HStack { TextField("Element", text: $element).frame(width: 48); Button("Insert") { workspace.editElement(element, insert: true) }; Button("Replace") { workspace.editElement(element, insert: false) }.disabled(workspace.selectedAtomIndices.isEmpty) }
                Toggle("Click to add this atom", isOn: Binding(get: { workspace.pendingElement != nil }, set: { enabled in
                    workspace.pendingAttachment = nil; workspace.isDraggingEnabled = false
                    workspace.pendingElement = enabled ? element : nil
                    workspace.buildingHint = enabled ? "Click an atom to add \(element). Right-click finishes." : ""
                })).disabled(element == "X")
                if !workspace.buildingHint.isEmpty { Text(workspace.buildingHint).font(.caption).foregroundStyle(.blue) }
                Button("Remove unused X sites") {
                    guard let frame = workspace.currentFrame else { return }
                    workspace.selectedAtomIndices = frame.atoms.indices.filter { frame.atoms[$0].element == "X" }
                    workspace.deleteSelectedAtoms(); workspace.pendingAttachment = nil; workspace.pendingElement = nil; workspace.buildingHint = ""
                }.disabled(!(workspace.currentFrame?.atoms.contains { $0.element == "X" } ?? false))
        }
    }
    private var chemistryControls: some View {
        VStack(alignment: .leading, spacing: 8) {
                heading("GEOMETRY CLEANUP & WORKFLOW")
                Toggle("Keep selected atoms fixed", isOn: $freezeSelection)
                HStack {
                    Button("Clean geometry · UFF") { chemistry.optimize(workspace, freezeSelection: freezeSelection) }.disabled(chemistry.busy || workspace.currentFrame == nil)
                    if chemistry.busy { ProgressView().controlSize(.small); Button("Cancel") { chemistry.cancel() } }
                }
                Text("UFF needs supported atom types and no X sites. Metal complexes may need a suitable MLIP or QM method.").font(.caption).foregroundStyle(.secondary)
                Button(chemistry.guiURL == nil ? "ChemRefine workflow…" : "Reopen ChemRefine workflow…") { chemistry.openWorkflow(workspace) }
                if chemistry.guiURL != nil { Button("New workflow from current geometry…") { chemistry.newWorkflow(workspace) } }
                Text("The local editor can validate, run and resume workflows. Configure installed engine paths under Executables; ORCA and MLIP weights are separate installations.").font(.caption).foregroundStyle(.secondary)
                if !chemistry.status.isEmpty { Text(chemistry.status).font(.caption).textSelection(.enabled) }
        }
    }
    private func chooseFragment(_ item: LibraryFragment) {
        imported = item.geometry; importedName = item.name; resetSite()
        workspace.isDraggingEnabled = false; workspace.pendingElement = nil
        workspace.pendingAttachment = fragment; workspace.pendingAttachmentLeaving = leaving
        workspace.buildingHint = "Click a host atom to attach \(item.name). Right-click finishes."
    }
    private func useSelection() {
        guard let frame = workspace.currentFrame else { return }
        imported = workspace.selectedAtomIndices.filter(frame.atoms.indices.contains).map { frame.atoms[$0] }
        importedName = "Selected fragment"; resetSite()
        workspace.pendingElement = nil; workspace.isDraggingEnabled = false
        workspace.pendingAttachment = sites.isEmpty ? nil : imported; workspace.pendingAttachmentLeaving = leaving
        workspace.buildingHint = sites.isEmpty ? "Include a terminal H or X in your selected fragment to define an attachment site." : "Click a host atom to attach the selected fragment. Right-click finishes."
    }
    private var savedFolder: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ChemViewer/Fragments") }
    private func saveFragment() {
        useSelection()
        guard let atoms = imported, !atoms.isEmpty else { return }
        do {
            try FileManager.default.createDirectory(at: savedFolder, withIntermediateDirectories: true)
            let panel = NSSavePanel(); panel.directoryURL = savedFolder; panel.nameFieldStringValue = "fragment.xyz"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let frame = MoleculeFrame(id: 0, atoms: atoms, comment: "User fragment; X atoms define attachment sites")
            try XYZWriter.string(frame: frame).write(to: url, atomically: true, encoding: .utf8)
        } catch { workspace.errorMessage = error.localizedDescription }
    }
    private func loadSavedFragment() { importFragment(directory: savedFolder) }
    private func heading(_ text: String) -> some View { VStack(alignment: .leading) { Divider(); Text(text).font(.caption.bold()) } }
    private func resetSite() { leaving = sites.first ?? -1 }
    private func transform(_ distance: Float, _ degrees: Float) { workspace.transformBuildingSelection(axis: axis, distance: distance, degrees: degrees) }
    private func importFragment(directory: URL? = nil) {
        let panel = NSOpenPanel(); panel.directoryURL = directory; panel.allowedContentTypes = [.plainText, .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { @MainActor in
            do {
                let atoms = try await Task.detached {
                    let data = try Data(contentsOf: url)
                    guard data.count <= 10_000_000, let text = String(data: data, encoding: .utf8) else { throw ParseError.malformed("Fragment must be a UTF-8 XYZ file smaller than 10 MB.") }
                    guard let first = try XYZParser.parse(text: text).frames.first else { throw ParseError.noGeometry }
                    return first.atoms
                }.value
                workspace.pendingAttachment = nil; workspace.pendingElement = nil
                imported = atoms; importedName = url.lastPathComponent; resetSite()
            } catch { workspace.errorMessage = error.localizedDescription }
        }
    }
}
