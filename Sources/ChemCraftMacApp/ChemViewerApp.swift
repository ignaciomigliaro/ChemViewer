import SwiftUI

@main
struct ChemViewerApp: App {
    @StateObject private var documents = DocumentTabs()
    private var workspace: WorkspaceStore { documents.activeWorkspace }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<WorkspaceStore, Value>) -> Binding<Value> {
        let tabs = documents
        return Binding(get: { tabs.activeWorkspace[keyPath: keyPath] }, set: { tabs.activeWorkspace[keyPath: keyPath] = $0 })
    }
    var body: some Scene {
        WindowGroup("ChemViewer " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")) {
            ContentView()
                .environmentObject(workspace)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Molecule") { workspace.startNewDocument() }.keyboardShortcut("n")
                Button(workspace.activeTab == "Draw" ? "Open Drawing…" : "Open…") { workspace.openFromMenu() }
                    .keyboardShortcut("o")
                Button("Close Document Tab") { documents.requestCloseActive() }.keyboardShortcut("w")
            }
            CommandGroup(after: .newItem) {
                Button("Remote files & SLURM…") { RemoteConnection.shared.presented = true }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                Button(workspace.activeTab == "Draw" ? "Undo Drawing Edit" : "Undo Geometry Edit") {
                    if workspace.activeTab == "Draw" { workspace.drawing.undo() } else { workspace.undoGeometry() }
                }.keyboardShortcut("z").disabled(workspace.activeTab == "Draw" ? !workspace.drawing.canUndo : !workspace.canUndoGeometry)
                Button(workspace.activeTab == "Draw" ? "Redo Drawing Edit" : "Redo Geometry Edit") {
                    if workspace.activeTab == "Draw" { workspace.drawing.redo() } else { workspace.redoGeometry() }
                }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(workspace.activeTab == "Draw" ? !workspace.drawing.canRedo : !workspace.canRedoGeometry)
            }
            CommandMenu("View") {
                ForEach(Array(["Image", "Abstract", "Source", "Coord", "Image/Abs", "ChemRefine", "Draw"].enumerated()), id: \.offset) { index, tab in
                    Button(tab) { workspace.activeTab = tab }.keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
                Toggle("Remote File Explorer", isOn: Binding(get: { RemoteConnection.shared.explorerVisible }, set: { RemoteConnection.shared.explorerVisible = $0 }))
                Toggle("Result Explorer", isOn: binding(\.showExplorer))
                Divider()
                Button("Fit and Center") { NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "reset") }
                Button("Front View") { NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "front") }
            }
            CommandMenu("Build") {
                Button("Fragment Library…") { workspace.presentFragmentLibrary() }.keyboardShortcut("b")
                Button("Add Atom…") { workspace.presentAtomPicker() }.keyboardShortcut("a", modifiers: [.command, .shift])
                Toggle("Build & Edit Panel", isOn: binding(\.isBuilderVisible)).keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Finish Placement") { workspace.clearSelection() }
            }
            CommandMenu("Display") {
                Picker("Drawing Style", selection: binding(\.renderingStyle)) {
                    ForEach(MolecularStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Toggle("Hydrogens", isOn: binding(\.showHydrogens))
                Picker("Atom Captions", selection: binding(\.atomCaption)) { ForEach(AtomCaption.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Toggle("Displacement Vectors", isOn: binding(\.showDisplacementVectors))
            }
            CommandMenu("Tools") {
                Button("Energy Landscape…") { workspace.isEnergyLandscapePresented = true }
                    .disabled((workspace.document?.frames.count ?? 0) < 2 && workspace.document?.nebProfile == nil)
                Button("Cartesian Coordinates") { workspace.activeTab = "Coord" }
                    .disabled(workspace.currentFrame == nil)
                Button("IR Spectrum") { workspace.isSpectrumPresented = true }
                    .disabled(!(workspace.document?.vibrationalModes.contains { $0.infraredIntensity != nil } ?? false))
                Button(workspace.isVibrating ? "Pause Frequency" : "Animate Frequency") { workspace.isVibrating.toggle() }
                    .disabled(workspace.selectedMode == nil)
                Button("Play / Pause Geometry Trajectory") { workspace.toggleTrajectoryPlayback() }
                    .disabled((workspace.document?.frames.count ?? 0) < 2 && workspace.document?.nebProfile == nil)
            }
            CommandGroup(replacing: .saveItem) {
                Button(workspace.activeTab == "Draw" ? "Save Drawing…" : "Save Project…") { workspace.saveFromMenu() }.keyboardShortcut("s")
                Button("Export ORCA Geometry…") { workspace.exportORCAGeometry() }
                Button("Export Current Geometry as XYZ") {
                    workspace.requestXYZExport()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(workspace.currentFrame == nil)
                Button("Export Animation as GIF…") { workspace.presentAnimationExport() }
                    .disabled(workspace.currentFrame == nil)
                Button("Export Image as PNG…") {
                    workspace.activeTab = "Image"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "export") }
                }.disabled(workspace.currentFrame == nil)
            }
        }
    }
}
