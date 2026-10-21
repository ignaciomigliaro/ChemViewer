import AppKit
import ChemCraftCore
import SwiftUI

struct DrawView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject var drawing: MoleculeDrawingStore
    @State private var multiplicity = 1
    @State private var showRingLibrary = false
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
                    Text("Chain: drag to draw a zigzag alkane. Bond: click an endpoint to extend at 120°, or drag to connect atoms. Option-drag allows other angles. Move: drag atoms or pan blank space. Scroll to zoom.")
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
                    Button { drawing.tool = .chain } label: {
                        HStack(spacing: 3) { ChainToolGlyph(); Text("Chain") }.padding(4)
                            .background(drawing.tool == .chain ? Color.teal.opacity(0.15) : .clear)
                    }.buttonStyle(.plain).help("Drag a zigzag carbon chain; one gesture is one undoable edit")
                        .accessibilityIdentifier("draw-chain")
                    ForEach(1...3, id: \.self) { order in
                        toolButton(order == 1 ? "Single" : order == 2 ? "Double" : "Triple", selected: drawing.tool == .bond && drawing.order == order && drawing.stereo == "none") { drawing.tool = .bond; drawing.order = order; drawing.stereo = "none" }
                    }
                    toolButton("Wedge", selected: drawing.tool == .bond && drawing.stereo == "up") { drawing.tool = .bond; drawing.order = 1; drawing.stereo = "up" }
                    toolButton("Dash", selected: drawing.tool == .bond && drawing.stereo == "down") { drawing.tool = .bond; drawing.order = 1; drawing.stereo = "down" }
                    Divider().frame(height: 22)
                    ForEach([DrawingTool.atom, .move, .erase], id: \.self) { tool in
                        toolButton(tool.rawValue, selected: drawing.tool == tool) { drawing.tool = tool }
                    }
                    Divider().frame(height: 22)
                    ringButton(.benzene, showName: true)
                    ForEach([SketchRingTemplate.cyclopropane, .cyclobutane, .cyclopentane, .cyclohexane, .cycloheptane, .cyclooctane], id: \.self) { template in
                        ringButton(template)
                    }
                    Button("More rings…") { showRingLibrary = true }
                        .popover(isPresented: $showRingLibrary) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Ring library").font(.headline)
                                LazyVGrid(columns: Array(repeating: GridItem(.fixed(100)), count: 4), spacing: 12) {
                                    ForEach(SketchRingTemplate.allCases, id: \.self) { template in
                                        Button { chooseRing(template); showRingLibrary = false } label: {
                                            VStack { RingTemplateGlyph(template: template).frame(width: 46, height: 46); Text(template.rawValue).font(.caption) }
                                                .frame(width: 96, height: 72)
                                        }.buttonStyle(.bordered)
                                    }
                                }
                                Text("Click blank space to place, or click an atom to share that ring vertex.").font(.caption).foregroundStyle(.secondary)
                            }.padding(16)
                        }
                    Menu("More") {
                        Button("Add positive formal charge") { drawing.tool = .positive }
                        Button("Add negative formal charge") { drawing.tool = .negative }
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
    private func chooseRing(_ template: SketchRingTemplate) {
        drawing.tool = .ring; drawing.ringTemplate = template
        drawing.ringSize = template.elements.count; drawing.aromatic = template == .benzene
    }
    private func ringButton(_ template: SketchRingTemplate, showName: Bool = false) -> some View {
        Button { chooseRing(template) } label: {
            HStack(spacing: 3) {
                RingTemplateGlyph(template: template).frame(width: 30, height: 30)
                if showName { Text(template.rawValue).font(.caption) }
            }.padding(3).background(drawing.tool == .ring && drawing.ringTemplate == template ? Color.teal.opacity(0.15) : .clear)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.25)))
        }.buttonStyle(.plain).help(template.rawValue).accessibilityLabel(template.rawValue)
            .accessibilityIdentifier("draw-ring-" + template.rawValue)
    }
    private func toolButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.system(size: 12, weight: selected ? .bold : .regular)).padding(.horizontal, 5).padding(.vertical, 4).background(selected ? Color.teal.opacity(0.15) : .clear).overlay(RoundedRectangle(cornerRadius: 3).stroke(selected ? Color.teal : Color.gray.opacity(0.3))) }.buttonStyle(.plain)
    }
    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("3D preview").font(.headline); Spacer(); if !drawing.previewIsCurrent && drawing.preview != nil { Text("Needs update").font(.caption).foregroundStyle(.orange) } }
            if let error = drawing.previewError {
                VStack(alignment: .leading, spacing: 6) {
                    Label("3D preview could not update", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Text(error).font(.caption).textSelection(.enabled).lineLimit(6)
                    Button("Retry 3D") { drawing.generate3D() }.disabled(drawing.busy)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color.red.opacity(0.08))
            } else if drawing.previewQueued || drawing.busy {
                HStack { ProgressView().controlSize(.small); Text(drawing.previewQueued ? "Waiting for drawing to pause…" : "Updating 3D structure…").font(.caption) }
            } else if !drawing.autoPreview && !drawing.previewIsCurrent && !drawing.graph.atoms.isEmpty {
                Text("Auto preview is off — click Generate 3D.").font(.caption).foregroundStyle(.orange)
            }
            if let result = drawing.preview, let frame = drawing.previewFrame {
                MoleculeMetalView(frame: frame, mode: nil, isAnimating: false, amplitude: 0, showDisplacementVectors: false,
                                  style: workspace.renderingStyle, showHydrogens: workspace.showHydrogens, selectedAtomIndices: .constant([]),
                                  documentID: workspace.documentIdentity,
                                  viewportState: workspace.drawingViewportState.flatMap { $0.0 == drawing.previewVersion ? $0.1 : nil },
                                  onSaveViewportState: { [workspace, version = drawing.previewVersion] in workspace.drawingViewportState = (version, $0) })
                    .frame(minHeight: 200).opacity(drawing.previewIsCurrent ? 1 : 0.35)
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
                Text("Generated conformer, not a conformer search").font(.caption).foregroundStyle(.secondary)
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
