import SwiftUI

struct MechanismCalculationList: View {
    let branch: MechanismBranch
    let stageNumber: Int
    @Binding var steps: [MechanismCalculation]
    let schema: MechanismSchema?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(branch.label).font(.headline)
                Text("\(steps.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                GeometryEditButton(title: "Add calculation", id: "mechanism-add-\(stageNumber)-\(branch.rawValue)") {
                    var step = MechanismCalculation(branch, expanded: true)
                    if branch == .ts && !steps.isEmpty { step.operation = "sp" }
                    steps.append(step)
                }.fixedSize()
            }
            if branch == .scoring {
                Text("Scoring calculations use the single-point operation (sp).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                if let binding = binding(step.id) {
                    MechanismCalculationView(branch: branch, step: binding, number: index + 1, schema: schema) {
                        Menu {
                            Button("Move up") { steps.swapAt(index, index - 1) }.disabled(index == 0)
                            Button("Move down") { steps.swapAt(index, index + 1) }.disabled(index + 1 == steps.count)
                            Divider()
                            Button("Remove calculation", role: .destructive) { steps.removeAll { $0.id == step.id } }
                        } label: { Label("Calculation actions", systemImage: "ellipsis.circle") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).labelStyle(.iconOnly)
                    }
                }
            }
        }.padding(10).background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private func binding(_ id: UUID) -> Binding<MechanismCalculation>? {
        guard let fallback = steps.first(where: { $0.id == id }) else { return nil }
        return Binding(get: { steps.first(where: { $0.id == id }) ?? fallback }, set: { value in
            if let index = steps.firstIndex(where: { $0.id == id }) { steps[index] = value }
        })
    }
}

private struct MechanismCalculationView<Actions: View>: View {
    let branch: MechanismBranch
    @Binding var step: MechanismCalculation
    let number: Int
    let schema: MechanismSchema?
    @ViewBuilder let actions: () -> Actions

    private var descriptor: MechanismSchema.Engine? { schema?.engines[step.engine] }
    private var engineNames: [String] { schema.map { Array(Set($0.engines.keys).union([step.engine])).sorted() } ?? [step.engine] }
    private var operations: [String] {
        descriptor?.operations ?? (step.engine == "orca" ? ["opt_sp", "sp", "freq"] : [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                DisclosureGroup(isExpanded: $step.expanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) { engineField; operationField; methodField }.fixedSize(horizontal: true, vertical: false)
                            VStack(alignment: .leading, spacing: 8) { engineField; operationField; methodField }
                        }
                        LabeledContent("Name") {
                            TextField("Optional", text: $step.name).textFieldStyle(.roundedBorder)
                        }
                        if branch != .scoring {
                            HStack {
                                Picker("On failure", selection: $step.onFailure) {
                                    Text("Stop").tag("stop")
                                    Text("Skip failed").tag("skip")
                                    Text("Keep best").tag("best")
                                }.fixedSize()
                                if descriptor?.capabilities.contains("nms") == true {
                                    Toggle("Normal-mode sampling", isOn: $step.nms)
                                }
                            }
                        }
                        if step.engine == "orca" || descriptor?.templateSuffix != nil {
                            DisclosureGroup("Input template") {
                                Text("Leave empty to generate a starter. Enter the full template for custom keywords and operations.")
                                    .font(.caption).foregroundStyle(.secondary)
                                TextEditor(text: $step.template)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minHeight: 100).border(.quaternary)
                                    .accessibilityLabel("Input template")
                            }
                        }
                        MechanismSettingsEditor(title: "Calculation settings", yaml: $step.settingsYAML,
                            keys: schema?.keys("StepConfig") ?? [],
                            extra: optionHelp)
                    }.padding(.top, 8)
                } label: {
                    HStack(spacing: 8) {
                        Text("\(number). \(step.name.isEmpty ? step.engine : step.name)").fontWeight(.medium).lineLimit(1)
                        if !step.name.isEmpty { Text(step.engine).foregroundStyle(.secondary) }
                        if !step.operation.isEmpty { Text(step.operation).foregroundStyle(.secondary) }
                        if !step.method.isEmpty { Text(step.method).foregroundStyle(.secondary).lineLimit(1) }
                    }.font(.callout)
                }
                actions().fixedSize()
            }
        }.padding(8).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }

    private var engineField: some View {
        Picker("Engine", selection: $step.engine) {
            ForEach(engineNames, id: \.self) { Text($0).tag($0) }
        }.frame(minWidth: 130).onChange(of: step.engine) { engine in
            let available = schema?.engines[engine]?.operations ?? []
            if branch != .scoring && !available.isEmpty && !available.contains(step.operation) {
                step.operation = ""
            }
            if step.method == "r2SCAN-3c" && engine != "orca" { step.method = "" }
            if engine == "orca" && step.method.isEmpty { step.method = "r2SCAN-3c" }
        }
    }

    @ViewBuilder private var operationField: some View {
        if branch == .scoring {
            LabeledContent("Operation", value: "sp").fixedSize()
        } else if operations.isEmpty {
            TextField("Operation", text: $step.operation).frame(minWidth: 115, idealWidth: 140)
        } else {
            Picker("Operation", selection: $step.operation) {
                Text("Infer from input").tag("")
                ForEach(operations, id: \.self) { Text($0).tag($0) }
                if !step.operation.isEmpty && !operations.contains(step.operation) {
                    Text(step.operation).tag(step.operation)
                }
            }.frame(minWidth: 140)
        }
    }

    private var methodField: some View {
        let label = step.engine.hasPrefix("mlip") ? "Model" : "Method"
        return LabeledContent(label) {
            TextField(label, text: $step.method)
                .textFieldStyle(.roundedBorder).frame(minWidth: 130, idealWidth: 160)
        }.help("Enter an engine keyword or model name, such as r2SCAN-3c or uma-s-1p2.")
    }

    private var optionHelp: String {
        var details: [String] = []
        if let options = descriptor?.optionsSchema?.keys, !options.isEmpty {
            details.append("options: " + options.joined(separator: ", "))
        }
        if descriptor?.capabilities.contains("nms") == true, let nms = schema?.nms.keys, !nms.isEmpty {
            details.append("NMS options: " + nms.joined(separator: ", "))
        }
        return details.joined(separator: "\n")
    }
}

struct MechanismSettingsEditor: View {
    let title: String
    @Binding var yaml: String
    var keys: [String] = []
    var extra = ""

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                if !keys.isEmpty {
                    Menu("Insert setting") {
                        ForEach(keys, id: \.self) { key in
                            Button(key) {
                                if yaml.isEmpty || yaml.last?.isNewline == true { yaml += "\(key): " }
                                else { yaml += "\n\(key): " }
                            }.disabled(yaml.split(separator: "\n").contains { $0.hasPrefix(key + ":") })
                        }
                    }.fixedSize()
                }
                if !extra.isEmpty { Text(extra).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                TextEditor(text: $yaml)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80).border(.quaternary)
                    .accessibilityLabel(title + " YAML")
            }.padding(.top, 5)
        } label: {
            Text(yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? title : title + " · edited")
                .font(.callout)
        }
    }
}
