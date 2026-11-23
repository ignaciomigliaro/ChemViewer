import ChemCraftCore
import SwiftUI

struct MechanismComposerView: View {
    @ObservedObject private var draft = MechanismDraft.shared
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox("Starting catalysts") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                GeometryEditButton(title: "Choose from BOS-TMC…", id: "mechanism-catalog") {
                                    draft.choosingCatalysts = true
                                    workspace.activeTab = "BosTMC"
                                }
                                Button("Import XYZ…") { draft.importXYZ() }
                            }
                            MechanismGeometryList(geometries: $draft.catalysts)
                            Text("Each catalyst runs as a separate alternative in the first stage.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach($draft.stages) { $stage in
                        MechanismStageView(stage: $stage, earlier: Array(draft.stages.prefix { $0.id != stage.id }))
                    }
                    GeometryEditButton(title: "Add stage", id: "mechanism-add-stage") { draft.addStage() }
                    GroupBox("Calculation settings") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Method", selection: $draft.engine) {
                                ForEach(MechanismDraft.Engine.allCases) { Text($0.rawValue).tag($0) }
                            }.fixedSize()
                            HStack {
                                Stepper("Total CPU cores  \(draft.cores)", value: $draft.cores, in: 1...256)
                                Stepper("Parallel mechanisms  \(draft.workers)", value: $draft.workers, in: 1...256)
                            }.fixedSize()
                            HStack {
                                Stepper("Variant limit  \(draft.maxVariants)", value: $draft.maxVariants, in: 1...4096)
                                Stepper("IDPP images  \(draft.images)", value: $draft.images, in: 3...99)
                            }.fixedSize()
                            DisclosureGroup("Advanced") {
                                Toggle("Allow changes in metal coordination during optimization", isOn: $draft.forceMetalContacts)
                                    .help("Accepts changed contacts involving a metal. ChemRefine still records the changes and checks ordinary bonds.")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(maxWidth: 880).padding(16).frame(maxWidth: .infinity)
            }.disabled(draft.saving)
            Divider()
            HStack(spacing: 12) {
                if draft.saving { ProgressView().controlSize(.small) }
                if !draft.notice.isEmpty {
                    Text(draft.notice).font(.caption).textSelection(.enabled)
                }
                Spacer()
                Text(draft.variantCount.map { "\($0.formatted()) combinations" } ?? "Too many combinations")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Create input.yaml…") { draft.save(workspace) }
                    .buttonStyle(.borderedProminent).disabled(draft.saving)
                    .accessibilityIdentifier("mechanism-create")
            }.padding(10)
        }
    }
}

private struct MechanismStageView: View {
    @Binding var stage: MechanismStageDraft
    let earlier: [MechanismStageDraft]
    @ObservedObject private var draft = MechanismDraft.shared
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        GroupBox("Stage \(earlier.count + 1)") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Stage name").font(.caption)
                        TextField("Stage name", text: $stage.name).labelsHidden()
                    }.frame(maxWidth: 230)
                    VStack(alignment: .leading) {
                        Text("Stage charge").font(.caption)
                        TextField("Stage charge", text: $stage.charge).labelsHidden()
                    }.frame(width: 100)
                    VStack(alignment: .leading) {
                        Text("Multiplicity").font(.caption)
                        TextField("Multiplicity", text: $stage.multiplicity).labelsHidden()
                    }.frame(width: 125)
                    Spacer()
                    if draft.stages.count > 1 {
                        Button("Remove stage", role: .destructive) { draft.removeStage(stage.id) }
                    }
                }
                if !earlier.isEmpty {
                    HStack {
                        Picker("Carry optimized product from", selection: $stage.carry) {
                            Text("None").tag(nil as UUID?)
                            ForEach(earlier) { Text($0.name).tag(Optional($0.id)) }
                        }.fixedSize()
                        if stage.carry != nil {
                            Picker("Select", selection: $stage.selector) {
                                ForEach(MechanismStageDraft.CarrySelector.allCases) { Text($0.rawValue).tag($0) }
                            }.fixedSize()
                        }
                    }
                    if stage.carry != nil && stage.selector == .smiles {
                        HStack {
                            TextField("Whole-molecule SMILES", text: $stage.selectSMILES)
                            TextField("Occurrence (optional, starts at 0)", text: $stage.selectIndex).frame(width: 235)
                        }
                    }
                }
                Divider()
                geometrySection("Substrate alternatives", caption: "Each XYZ runs separately for every catalyst combination.",
                                geometries: $stage.substrates, kind: .substrate)
                geometrySection("Fixed reagents", caption: "Every listed reagent is included together.",
                                geometries: $stage.reagents, kind: .reagent)
                Divider()
                HStack {
                    Text("Initial coordination core").font(.headline)
                    Text("Optional").foregroundStyle(.secondary)
                    Spacer()
                    geometryActions(.initialCore)
                }
                if let initial = Binding($stage.initialCore) {
                    coreControls(initial) { stage.initialCore = nil }
                }
                Divider()
                HStack {
                    Picker("Product definition", selection: $stage.productKind) {
                        ForEach(MechanismStageDraft.ProductKind.allCases) { Text($0.rawValue).tag($0) }
                    }.fixedSize()
                    Spacer()
                    if stage.productKind == .core { geometryActions(.productCore) }
                    if stage.productKind == .xyz { geometryActions(.productXYZ) }
                }
                switch stage.productKind {
                case .core:
                    if let product = Binding($stage.productCore) {
                        coreControls(product) { stage.productCore = nil }
                    } else {
                        Text("Build the product motif with its metal and the atoms whose arrangement changes.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .xyz:
                    if let xyz = stage.productXYZ {
                        HStack {
                            Text(xyz.name)
                            Spacer()
                            Button("Remove product geometry") { stage.productXYZ = nil }
                        }
                    }
                case .smiles:
                    TextField("Complete product SMILES including byproducts", text: $stage.productSMILES)
                }
            }.padding(.vertical, 4)
        }
    }

    private func geometrySection(_ title: String, caption: String, geometries: Binding<[MechanismGeometry]>, kind: MechanismCapture) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                geometryActions(kind)
            }
            MechanismGeometryList(geometries: geometries)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func geometryActions(_ kind: MechanismCapture) -> some View {
        let target = MechanismDraft.CaptureTarget(stage: stage.id, kind: kind)
        return HStack {
            Button("Import XYZ…") { draft.importXYZ(to: target) }
            GeometryEditButton(title: kind.isCore ? "Build in 3D…" : "Use 3D builder…", id: "mechanism-build-\(kind)") {
                draft.pending = target
                draft.notice = ""
                workspace.activeTab = "Image"
            }
        }
    }

    private func coreControls(_ core: Binding<MechanismCore>, remove: @escaping () -> Void) -> some View {
        HStack {
            Text(core.wrappedValue.geometry.name).lineLimit(1)
            Text("\(core.wrappedValue.geometry.elements.count) atoms").foregroundStyle(.secondary)
            Spacer()
            Picker("Metal anchor", selection: core.anchor) {
                ForEach(core.wrappedValue.geometry.metalRows, id: \.self) { row in
                    Text("\(core.wrappedValue.geometry.elements[row - 1]) · XYZ row \(row)").tag(row)
                }
            }.fixedSize()
            Stepper("Placements  \(core.wrappedValue.placements)", value: core.placements, in: 1...16).fixedSize()
            Button("Remove", action: remove)
        }.font(.caption)
    }
}

private struct MechanismGeometryList: View {
    @Binding var geometries: [MechanismGeometry]

    var body: some View {
        ForEach($geometries) { $geometry in
            HStack {
                Text(geometry.name).lineLimit(1)
                Text("\(geometry.elements.count) atoms").foregroundStyle(.secondary)
                Spacer()
                Text("Source charge").font(.caption).foregroundStyle(.secondary)
                TextField("Charge", text: $geometry.charge).labelsHidden().frame(width: 65)
                Button {
                    let id = geometry.id
                    geometries.removeAll { $0.id == id }
                } label: { Label("Remove \(geometry.name)", systemImage: "xmark.circle") }
                    .labelStyle(.iconOnly)
            }
        }
    }
}

struct MechanismCaptureBar: View {
    let target: MechanismDraft.CaptureTarget
    @ObservedObject private var draft = MechanismDraft.shared
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        HStack {
            Text(target.kind.rawValue).font(.headline)
            if !draft.notice.isEmpty { Text(draft.notice).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button("New structure") {
                if let documents = workspace.documents { documents.newMolecule() }
                else { workspace.newMolecule() }
            }
            GeometryEditButton(title: "Capture selected atoms", id: "mechanism-capture-selection") { draft.capture(workspace, target: target, selectionOnly: true) }
                .disabled(workspace.selectedAtomIndices.isEmpty)
            GeometryEditButton(title: "Capture whole structure", id: "mechanism-capture-whole") { draft.capture(workspace, target: target, selectionOnly: false) }
                .disabled(workspace.currentFrame?.atoms.isEmpty ?? true)
            Button("Back to mechanism") {
                draft.pending = nil
                workspace.activeTab = "ChemRefine"
            }
        }.padding(8)
    }
}
