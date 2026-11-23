import ChemCraftCore
import SwiftUI

struct MechanismComposerView: View {
    @ObservedObject private var draft = MechanismDraft.shared
    @EnvironmentObject private var workspace: WorkspaceStore

    @State private var reviewing = false
    @State private var preview = ""
    @State private var loadingPreview = false

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
                                }.fixedSize()
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
                    GeometryEditButton(title: "Add stage", id: "mechanism-add-stage") { draft.addStage() }.fixedSize()
                    GroupBox("Workflow settings") {
                        VStack(alignment: .leading, spacing: 8) {
                            ViewThatFits(in: .horizontal) {
                                HStack { budgets }.fixedSize()
                                VStack(alignment: .leading) { budgets }
                            }
                            Toggle("Allow metal coordination changes", isOn: $draft.forceMetalContacts)
                            MechanismSettingsEditor(title: "Mechanism settings", yaml: $draft.mechanismYAML,
                                keys: draft.schema?.keys("MechanismConfig") ?? [])
                            MechanismSettingsEditor(title: "Top-level input.yaml settings", yaml: $draft.workflowYAML,
                                keys: draft.schema?.keys() ?? [])
                            if !draft.schemaError.isEmpty {
                                HStack {
                                    Text("ChemRefine schema unavailable").foregroundStyle(.secondary).help(draft.schemaError)
                                    Button("Retry") { Task { await draft.loadSchema() } }
                                }.font(.caption)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(maxWidth: 880).padding(16).frame(maxWidth: .infinity)
            }.disabled(draft.saving)
            Divider()
            if !draft.notice.isEmpty {
                Text(draft.notice).font(.caption).textSelection(.enabled)
                    .lineLimit(4).help(draft.notice)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.top, 8)
            }
            HStack(spacing: 12) {
                if draft.saving || loadingPreview { ProgressView().controlSize(.small) }
                Spacer()
                Text(draft.variantCount.map { "\($0.formatted()) combinations" } ?? "Too many combinations")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Review YAML") {
                    loadingPreview = true
                    Task {
                        defer { loadingPreview = false }
                        do {
                            preview = try await draft.previewYAML()
                            reviewing = true
                        } catch { draft.notice = error.localizedDescription }
                    }
                }.disabled(draft.saving || loadingPreview)
                Button("Create input.yaml…") { draft.save(workspace) }
                    .buttonStyle(.borderedProminent).disabled(draft.saving)
                    .accessibilityIdentifier("mechanism-create")
            }.padding(10)
        }
        .task { await draft.loadSchema() }
        .sheet(isPresented: $reviewing) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("input.yaml").font(.headline)
                    Spacer()
                    Button("Done") { reviewing = false }
                }
                ScrollView([.horizontal, .vertical]) {
                    Text(preview).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding().frame(minWidth: 640, minHeight: 490)
        }
    }

    @ViewBuilder private var budgets: some View {
        Stepper("CPU cores  \(draft.cores)", value: $draft.cores, in: 1...256)
        Stepper("GPUs  \(draft.maxGPUs)", value: $draft.maxGPUs, in: 0...64)
        Stepper("Parallel variants  \(draft.workers)", value: $draft.workers, in: 1...256)
        Stepper("Variant limit  \(draft.maxVariants)", value: $draft.maxVariants, in: 1...4096)
    }
}

private struct MechanismStageView: View {
    @Binding var stage: MechanismStageDraft
    let earlier: [MechanismStageDraft]
    @ObservedObject private var draft = MechanismDraft.shared
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $stage.expanded) {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Stage section", selection: $stage.section) {
                        ForEach(MechanismStageDraft.Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().fixedSize()
                    if stage.section == .structures { structures }
                    else { calculations }
                    MechanismSettingsEditor(title: "Reaction stage settings", yaml: $stage.settingsYAML,
                        keys: draft.schema?.keys("MechanismStage") ?? [])
                }.padding(.top, 10)
            } label: {
                HStack {
                    Text("Stage \(earlier.count + 1)").font(.headline)
                    Text(stage.name.isEmpty ? "Untitled" : stage.name).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text("\(calculationCount) calculations").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var calculationCount: Int {
        stage.reactantSteps.count + stage.productSteps.count + stage.scoringSteps.count + stage.tsSteps.count
    }

    private var calculations: some View {
        VStack(alignment: .leading, spacing: 8) {
            let number = earlier.count + 1
            Picker("Calculation group", selection: $stage.calculationBranch) {
                Text("Reactants").tag(MechanismBranch.reactant)
                Text("Products").tag(MechanismBranch.product)
                Text("Path & scoring").tag(MechanismBranch.scoring)
                Text("TS refinement").tag(MechanismBranch.ts)
            }.pickerStyle(.segmented)
            switch stage.calculationBranch {
            case .reactant:
                MechanismCalculationList(branch: .reactant, stageNumber: number, steps: $stage.reactantSteps, schema: draft.schema)
            case .product:
                MechanismCalculationList(branch: .product, stageNumber: number, steps: $stage.productSteps, schema: draft.schema)
            case .scoring:
                GroupBox("Transition-state guess") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Picker("Guesser", selection: $stage.guesser) {
                                ForEach(draft.schema?.guessers ?? ["idpp"], id: \.self) { Text($0).tag($0) }
                            }.fixedSize()
                            Stepper("Images  \(stage.images)", value: $stage.images, in: 3...999).fixedSize()
                            Text("Timeout")
                            TextField("Seconds", value: $stage.guesserTimeout, format: .number).frame(width: 60)
                            Text("s").foregroundStyle(.secondary)
                        }
                        MechanismSettingsEditor(title: "Guesser settings", yaml: $stage.guesserYAML,
                            keys: draft.schema?.keys("TSGuesserConfig") ?? [])
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                MechanismCalculationList(branch: .scoring, stageNumber: number, steps: $stage.scoringSteps, schema: draft.schema)
            case .ts:
                MechanismCalculationList(branch: .ts, stageNumber: number, steps: $stage.tsSteps, schema: draft.schema)
            }
        }
    }

    private var structures: some View {
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
                MechanismSettingsEditor(title: "Reactant settings", yaml: $stage.reactantYAML,
                    keys: draft.schema?.keys("MechanismReactant") ?? [])
                MechanismSettingsEditor(title: "Product settings", yaml: $stage.productYAML,
                    keys: draft.schema?.keys("MechanismProduct") ?? [])
            }.padding(.vertical, 4)
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
            }.fixedSize()
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
