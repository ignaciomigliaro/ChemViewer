import SwiftUI

struct ClassicButtonStyle: ButtonStyle {
    var badge = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.black)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(configuration.isPressed ? Color(white: 0.78) : Color(white: 0.91))
            .overlay(Rectangle().stroke(Color(white: 0.48), lineWidth: 1))
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.8)).frame(height: 1) }
    }
}

struct ClassicMenuBar: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    private func action(_ value: String) { NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: value) }
    var body: some View {
        HStack(spacing: 22) {
            Menu("File") {
                Button("New Molecule") { workspace.newMolecule(); workspace.presentFragmentLibrary() }
                Button("Open…") { workspace.isImporterPresented = true }
                Button("Save Project…") { workspace.saveBuildingProject() }
                Button("Export XYZ…") { workspace.requestXYZExport() }
                Button("Export ORCA Geometry…") { workspace.exportORCAGeometry() }
                Button("Export PNG…") { action("export") }
                Button("Export GIF…") { workspace.presentAnimationExport() }
            }
            Menu("Edit") {
                Button("Undo") { workspace.undoGeometry() }.disabled(!workspace.canUndoGeometry)
                Button("Redo") { workspace.redoGeometry() }.disabled(!workspace.canRedoGeometry)
                Button("Fragment Library…") { workspace.presentFragmentLibrary() }
                Button("Duplicate Selected") { workspace.duplicateSelectedAtoms() }
                Button("Delete Selected") { workspace.deleteSelectedAtoms() }
            }
            Menu("View") {
                ForEach(["Image", "Abstract", "Source", "Coord", "Image/Abs", "ChemRefine"], id: \.self) { tab in Button(tab) { workspace.activeTab = tab } }
                Toggle("Result Explorer", isOn: $workspace.showExplorer)
                Toggle("Build & Edit Panel", isOn: $workspace.isBuilderVisible)
                Button("Fit Molecule") { action("reset") }
                Button("Front View") { action("front") }
            }
            Menu("Display") {
                Picker("Drawing Style", selection: $workspace.renderingStyle) { ForEach(MolecularStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Toggle("Frequency Vectors", isOn: $workspace.showDisplacementVectors)
                Toggle("Hydrogens", isOn: $workspace.showHydrogens)
                Picker("Atom Captions", selection: $workspace.atomCaption) { ForEach(AtomCaption.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            }
            Menu("Tools") {
                Button("Select Connected Molecule") { workspace.selectConnectedGroup() }
                Button("Coordinates") { workspace.activeTab = "Coord" }
                Button("Energy Landscape…") { workspace.isEnergyLandscapePresented = true }
            }
            Menu("Compute") {
                Button("Frequencies / Animation") { workspace.isBuilderVisible = true }
                Button("Play / Pause Frequency") { workspace.isVibrating.toggle() }
                Button("IR Spectrum…") { workspace.isSpectrumPresented = true }
            }
            Menu("Help") { Text("Open a calculation, or use + to build from fragments. Right-click clears selection. Built structures are initial approximations.") }
            Spacer()
        }.menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
            .font(.system(size: 17)).padding(.horizontal, 12).padding(.vertical, 4).background(.white)
    }
}
