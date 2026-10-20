import AppKit
import ChemCraftCore
import SwiftUI

struct DrawView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject var drawing: MoleculeDrawingStore
    @State private var multiplicity = 1
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                VStack(spacing: 0) {
                    HStack {
                        Text("2D structure").font(.headline)
                        Spacer()
                        Text("\(drawing.graph.atoms.count) atoms · \(drawing.graph.bonds.count) bonds").font(.caption).foregroundStyle(.secondary)
                        Button("Fit") { drawing.fit() }
                    }.padding(10)
                    DrawingCanvas(drawing: drawing).frame(minWidth: 400, minHeight: 300)
                    Divider()
                    Text("Bond: click to start a chain, click an atom to extend, or drag between atoms to connect. Move: drag atoms; drag blank space to pan. Scroll to zoom.")
                        .font(.caption).foregroundStyle(.secondary).padding(10)
                }.frame(minWidth: 430, idealWidth: 650)
                previewPanel.frame(minWidth: 290, idealWidth: 380)
            }
            Divider()
            HStack {
                if drawing.busy { ProgressView().controlSize(.small); Button("Cancel") { drawing.cancel() } }
                Text(drawing.status).font(.caption).textSelection(.enabled).lineLimit(3)
                Spacer()
            }.padding(10)
        }
        .sheet(isPresented: $drawing.showElements) {
            PeriodicTableView(onSelect: { symbol in if symbol != "X" { drawing.element = symbol; drawing.tool = .atom } })
        }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Draw").font(.title2.bold())
                Button("Open…") { drawing.openDrawing() }
                Button("Save…") { drawing.saveDrawing() }.disabled(drawing.graph.atoms.isEmpty)
                Button("Clear") { drawing.commit(MolecularSketch()) }.disabled(drawing.graph.atoms.isEmpty)
                Button { drawing.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!drawing.canUndo).help("Undo drawing edit")
                Button { drawing.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!drawing.canRedo).help("Redo drawing edit")
                Button("Clean 2D") { drawing.clean2D() }.disabled(drawing.graph.atoms.isEmpty || drawing.busy)
                Spacer()
                Toggle("Auto 3D preview", isOn: $drawing.autoPreview).toggleStyle(.checkbox)
                Button("Generate 3D") { drawing.generate3D() }.disabled(drawing.graph.atoms.isEmpty || drawing.busy)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(1...3, id: \.self) { order in
                        toolButton(order == 1 ? "Single" : order == 2 ? "Double" : "Triple", selected: drawing.tool == .bond && drawing.order == order && drawing.stereo == "none") { drawing.tool = .bond; drawing.order = order; drawing.stereo = "none" }
                    }
                    toolButton("Wedge", selected: drawing.tool == .bond && drawing.stereo == "up") { drawing.tool = .bond; drawing.order = 1; drawing.stereo = "up" }
                    toolButton("Dash", selected: drawing.tool == .bond && drawing.stereo == "down") { drawing.tool = .bond; drawing.order = 1; drawing.stereo = "down" }
                    Divider().frame(height: 22)
                    ForEach([DrawingTool.atom, .move, .erase, .positive, .negative], id: \.self) { tool in
                        toolButton(tool.rawValue, selected: drawing.tool == tool) { drawing.tool = tool }
                    }
                    Menu(drawing.tool == .ring ? (drawing.aromatic ? "Benzene" : "Ring \(drawing.ringSize)") : "Rings") {
                        Button("Benzene") { drawing.tool = .ring; drawing.ringSize = 6; drawing.aromatic = true }
                        ForEach(3...8, id: \.self) { count in Button("\(count)-membered ring") { drawing.tool = .ring; drawing.ringSize = count; drawing.aromatic = false } }
                    }.fixedSize()
                }
            }
            HStack(spacing: 5) {
                Text("Element:").font(.caption)
                ForEach(["C", "N", "O", "S", "P", "F", "Cl", "Br", "I", "H"], id: \.self) { symbol in
                    toolButton(symbol, selected: drawing.element == symbol) { drawing.element = symbol }
                }
                Button("Periodic table…") { drawing.showElements = true }
                Spacer()
            }
            HStack {
                TextField("Paste SMILES to start from a known structure", text: $drawing.smilesInput).textFieldStyle(.roundedBorder).onSubmit { drawing.importSMILES() }
                Button("Load SMILES") { drawing.importSMILES() }.disabled(drawing.smilesInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || drawing.busy)
            }
        }.padding(10)
    }
    private func toolButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.system(size: 12, weight: selected ? .bold : .regular)).padding(.horizontal, 5).padding(.vertical, 4).background(selected ? Color.teal.opacity(0.15) : .clear).overlay(RoundedRectangle(cornerRadius: 3).stroke(selected ? Color.teal : Color.gray.opacity(0.3))) }.buttonStyle(.plain)
    }
    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("3D preview").font(.headline); Spacer(); if !drawing.previewIsCurrent && drawing.preview != nil { Text("Needs update").font(.caption).foregroundStyle(.orange) } }
            if let result = drawing.preview, let frame = result.frame {
                MoleculeMetalView(frame: frame, mode: nil, isAnimating: false, amplitude: 0, showDisplacementVectors: false,
                                  style: workspace.renderingStyle, showHydrogens: workspace.showHydrogens, selectedAtomIndices: .constant([]))
                    .frame(minHeight: 200)
                Text(result.formula ?? "").font(.title3.bold())
                Text(result.smiles).font(.caption.monospaced()).textSelection(.enabled).lineLimit(3)
                HStack {
                    Button("Copy SMILES") { _ = ClipboardSupport.copy(result.smiles) }
                    Button("Copy XYZ") { _ = ClipboardSupport.copy(XYZWriter.string(frame: frame)) }
                }.disabled(!drawing.previewIsCurrent)
                if (result.radicalElectrons ?? 0) > 0 {
                    Text("Radical electrons: \(result.radicalElectrons ?? 0). Choose the intended spin multiplicity.").font(.caption)
                }
                Stepper("Multiplicity: \(multiplicity)", value: $multiplicity, in: 1...15)
                Text("Charge: \(result.charge ?? 0) · generated conformer, not a conformer search").font(.caption).foregroundStyle(.secondary)
                Button("Use 3D in Viewer") { drawing.use3D(in: workspace, multiplicity: multiplicity) }.disabled(!drawing.previewIsCurrent || drawing.busy)
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("use-drawing-3d")
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "cube.transparent").font(.system(size: 42)).foregroundStyle(.teal)
                    Text("Draw in 2D. Build in 3D.").font(.headline)
                    Text("RDKit adds hydrogens, generates an ETKDG conformer and applies UFF where parameters are available. All processing stays on this Mac.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(12)
    }
}
