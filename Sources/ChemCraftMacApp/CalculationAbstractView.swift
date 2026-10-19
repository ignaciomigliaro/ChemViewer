import ChemCraftCore
import SwiftUI

struct CalculationAbstractView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @State private var thermoID: Int?
    @State private var baseChoice = "final"
    @State private var copied = ""
    var showStructure = false
    private var records: [EnergyRecord] { workspace.document?.energyRecords.filter { $0.frameIndex == workspace.frameIndex } ?? [] }
    private var thermos: [ThermochemistryRecord] { workspace.document?.thermochemistry.filter { $0.frameIndex == workspace.frameIndex } ?? [] }
    private var thermo: ThermochemistryRecord? { thermos.first { $0.id == thermoID } ?? thermos.last }
    private var baseEnergy: Double? {
        switch baseChoice {
        case "thermo": return thermo?.electronic?.hartree
        case "scf": return records.last { $0.kind == .scf }?.hartree()
        default: return workspace.currentFrame?.energyHartree
        }
    }
    private var values: [(String, Double)] {
        guard !workspace.isFrameEdited(workspace.frameIndex) else { return [] }
        var result: [(String, Double)] = []
        if let value = records.last(where: { $0.kind == .scf })?.hartree() { result.append(("SCF", value)) }
        if let value = workspace.currentFrame?.energyHartree { result.append(("Electronic E", value)) }
        if let t = thermo {
            if let value = t.zeroPoint?.hartree { result.append(("ZPE", value)) }
            if let value = t.enthalpy?.hartree { result.append(("Enthalpy H", value)) }
            if let value = t.gibbs?.hartree { result.append(("Gibbs G", value)) }
        }
        return result
    }
    private var sums: [(String, Double)] {
        guard !workspace.isFrameEdited(workspace.frameIndex), let t = thermo, let baseEnergy else { return [] }
        var result: [(String, Double)] = [("Electronic base", baseEnergy)]
        if let value = t.enthalpyCorrection { result.append(("H − E correction", value)) }
        if let value = t.gibbsCorrection { result.append(("G − E correction", value)) }
        if let value = t.summedEnthalpy(electronicEnergy: baseEnergy) { result.append(("E + H correction", value)) }
        if let value = t.summedGibbs(electronicEnergy: baseEnergy) { result.append(("E + G correction", value)) }
        return result
    }
    var body: some View {
        if let document = workspace.document {
            VStack(spacing: 0) {
                HStack {
                    Text(document.title).font(.headline).lineLimit(1)
                    Spacer()
                    Button("Energy landscape…") { workspace.isEnergyLandscapePresented = true }.disabled(document.frames.count < 2 && document.nebProfile == nil)
                }.padding(12)
                Divider()
                HSplitView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if document.sourceFormat == "XYZ" && document.energyRecords.contains(where: { $0.unit == nil }) {
                                Picker("XYZ input unit", selection: $workspace.xyzEnergyUnit) {
                                    Text("Choose unit…").tag(nil as EnergyUnit?)
                                    ForEach(EnergyUnit.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                                }
                            }
                            if document.frames.count > 1 {
                                Text("Geometries • Eh").font(.caption).foregroundStyle(.secondary)
                                ForEach(Array(document.frames.enumerated()), id: \.offset) { index, frame in
                                    HStack {
                                        Button { workspace.selectFrame(index) } label: {
                                            Label("\(index + 1)", systemImage: workspace.frameIndex == index ? "circle.inset.filled" : "circle")
                                        }.buttonStyle(.plain)
                                        Spacer()
                                        if let energy = frame.energyHartree {
                                            Text(ClipboardSupport.number(energy)).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                            copyButton(ClipboardSupport.number(energy), key: "frame-\(index)")
                                        } else { Text(workspace.isFrameEdited(index) ? "Edited" : "—").foregroundStyle(.secondary) }
                                    }.padding(5).background(workspace.frameIndex == index ? Color.accentColor.opacity(0.08) : .clear)
                                }
                                Divider()
                            }
                            if workspace.isFrameEdited(workspace.frameIndex) { Text("Edited geometry • energy not recalculated").font(.caption).foregroundStyle(.secondary) }
                            else {
                                HStack { Text("Geometry \(workspace.frameIndex + 1) • Eh").font(.caption).foregroundStyle(.secondary); Spacer() }
                                ForEach(values, id: \.0) { row in valueRow(row) }
                            }
                            if !thermos.isEmpty && !workspace.isFrameEdited(workspace.frameIndex) {
                                if thermos.count > 1 {
                                    Picker("Thermochemistry", selection: Binding(get: { thermo?.id ?? 0 }, set: { thermoID = $0 })) {
                                        ForEach(thermos) { item in Text((item.temperatureKelvin.map { String(format: "%.2f K", $0) } ?? "Temperature unavailable") + " • line \(item.sourceLine)").tag(item.id) }
                                    }
                                }
                                if let t = thermo {
                                    HStack {
                                        if let temperature = t.temperatureKelvin { Text("\(temperature, specifier: "%.2f") K") }
                                        if let pressure = t.pressure { Text(pressure) }
                                    }.font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            if !showStructure { Button("View structure") { workspace.activeTab = "Image/Abs" }.font(.caption) }
                            DisclosureGroup("Output details") {
                                VStack(alignment: .leading, spacing: 7) {
                                    ForEach(Array(workspace.calculationFacts.enumerated()), id: \.offset) { _, fact in
                                        HStack { Text("Job \(fact.job + 1) · \(fact.label): \(fact.value) \(fact.unit)").textSelection(.enabled); Button("Line \(fact.line)") { workspace.showSource(line: fact.line) } }.font(.caption)
                                    }
                                    ForEach(records) { record in
                                        Text(record.sourceText.trimmingCharacters(in: .whitespaces)).font(.caption.monospaced()).textSelection(.enabled)
                                        Button("Source line \(record.sourceLine)") { workspace.showSource(line: record.sourceLine) }.font(.caption)
                                    }
                                    if let t = thermo { Button("Thermochemistry source") { workspace.showSource(line: t.sourceLine) }.font(.caption) }
                                    if !workspace.availableModes.isEmpty {
                                        Text("Frequencies (cm⁻¹)").font(.caption.bold())
                                        ForEach(workspace.availableModes) { mode in
                                            Button("\(mode.index): \(mode.frequencyCM1, specifier: "%.2f")") {
                                                workspace.selectMode(mode.index); workspace.isVibrating = true; workspace.activeTab = "Image/Abs"
                                            }.disabled(mode.displacements.isEmpty)
                                        }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5)
                            }.font(.caption)
                            if thermo != nil && !workspace.isFrameEdited(workspace.frameIndex) {
                                Divider()
                                HStack { Text("Sums • Eh").font(.headline); Spacer() }
                                Picker("Electronic base", selection: $baseChoice) {
                                    Text("Final energy").tag("final")
                                    if records.contains(where: { $0.kind == .scf }) { Text("SCF").tag("scf") }
                                    if thermo?.electronic != nil { Text("Thermochemistry E").tag("thermo") }
                                }
                                ForEach(sums, id: \.0) { row in valueRow(row) }
                            }
                            HStack {
                                Button("Copy table") { _ = ClipboardSupport.copy("Quantity\tEh\n" + (values + sums).map { $0.0 + "\t" + ClipboardSupport.number($0.1) }.joined(separator: "\n")) }
                                Button("Copy values") { _ = ClipboardSupport.copy((values + sums).map { ClipboardSupport.number($0.1) }.joined(separator: "\t")) }
                            }.disabled(values.isEmpty && sums.isEmpty)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minWidth: 275)
                    if showStructure, let frame = workspace.currentFrame {
                        MoleculeMetalView(frame: frame, mode: nil, isAnimating: false, amplitude: 0, showDisplacementVectors: false,
                            style: workspace.renderingStyle,
                                    showHydrogens: workspace.showHydrogens, atomCaption: workspace.atomCaption, vibrationSpeed: workspace.vibrationSpeed, selectedAtomIndices: $workspace.selectedAtomIndices,
                            showMeasurementOverlay: workspace.showMeasurementOverlay,
                    draggingEnabled: workspace.isDraggingEnabled, dragAxis: workspace.dragAxis,
                            onClearSelection: workspace.clearSelection,
                            onManipulationSelection: { _ = workspace.selectManipulationSeed($0) },
                            onBeginAtomDrag: workspace.beginAtomDrag,
                    onDragAtomIndices: { workspace.manipulationIndices }, onPreviewAtomDrag: workspace.previewAtomDrag,
                            onFinishAtomDrag: workspace.finishAtomDrag, onRenderingFailure: { workspace.errorMessage = $0 })
                            .frame(minWidth: 180, idealWidth: 280)
                    }
                }
            }.background(Color.white)
        } else { Text("Open an ORCA output or XYZ structure.").frame(maxWidth: .infinity, maxHeight: .infinity) }
    }
    private func valueRow(_ row: (String, Double)) -> some View {
        HStack(spacing: 5) {
            Text(row.0).font(.caption)
            Spacer(minLength: 4)
            Text(ClipboardSupport.number(row.1)).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            copyButton(ClipboardSupport.number(row.1), key: row.0)
        }
    }
    private func copyButton(_ text: String, key: String) -> some View {
        Button { if ClipboardSupport.copy(text) { copied = key } } label: { Image(systemName: copied == key ? "checkmark" : "doc.on.doc") }
            .buttonStyle(.borderless).help("Copy number only").accessibilityLabel("Copy \(key)")
    }
}
