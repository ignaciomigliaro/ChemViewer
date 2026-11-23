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
                    var step = MechanismCalculation(branch)
                    if branch == .ts && !steps.isEmpty { step.operation = nil }
                    steps.append(step)
                }.fixedSize()
            }
            if steps.isEmpty && (branch == .reactant || branch == .product) {
                Text("Optional. Add a calculation to prepare this endpoint.")
                    .font(.callout).foregroundStyle(.secondary)
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
            HStack {
                Text(step.name.isEmpty ? "Calculation \(number)" : "\(number). \(step.name)").font(.headline)
                Spacer()
                actions().fixedSize()
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 14) { engineField; operationField; methodField }
                VStack(alignment: .leading, spacing: 8) { engineField; operationField; methodField }
            }
            DisclosureGroup("Calculation details", isExpanded: $step.expanded) {
                VStack(alignment: .leading, spacing: 8) {
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
                }.padding(.top, 6)
            }
        }.padding(8).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
    }

    private var engineField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Engine").font(.caption).foregroundStyle(.secondary)
            Picker("Engine", selection: $step.engine) {
                ForEach(engineNames, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().frame(minWidth: 105)
        }.onChange(of: step.engine) { engine in
            let available = schema?.engines[engine]?.operations ?? []
            if branch != .scoring, let operation = step.operation, !operation.isEmpty, !available.contains(operation) {
                step.operation = nil
            }
        }
    }

    private var operationField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Operation").font(.caption).foregroundStyle(.secondary)
            if branch == .scoring {
                Text("Single point").frame(height: 22)
            } else {
                Picker("Operation", selection: $step.operation) {
                    if step.operation == nil { Text("Choose operation…").tag(String?.none) }
                    Text("Infer from input").tag(Optional(""))
                    ForEach(operations, id: \.self) { op in
                        Text(["opt_sp": "Geometry optimization", "sp": "Single point", "freq": "Frequencies"][op] ?? op).tag(Optional(op))
                    }
                }.labelsHidden().frame(minWidth: 150)
            }
        }
    }

    private var methodField: some View {
        let label = step.engine.hasPrefix("mlip") ? "Model" : "Method"
        return VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label == "Method" ? "Enter method" : "Enter model", text: $step.method)
                .textFieldStyle(.roundedBorder).frame(minWidth: 120)
                .accessibilityLabel(label)
        }
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
