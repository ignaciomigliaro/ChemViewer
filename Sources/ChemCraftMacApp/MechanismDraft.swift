import AppKit
import ChemCraftCore
import SwiftUI
import UniformTypeIdentifiers

struct MechanismGeometry: Identifiable {
    let id = UUID()
    let name: String
    let xyz: String
    let elements: [String]
    let multiplicity: Int?
    var charge: String

    init(name: String, xyz: String, charge: String = "", multiplicity: Int? = nil) throws {
        let parsed = try XYZParser.parse(text: xyz, title: name)
        guard parsed.frames.count == 1, let frame = parsed.frames.first, !frame.atoms.isEmpty else {
            throw ParseError.malformed("Use one nonempty XYZ structure per entry.")
        }
        let elements = frame.atoms.map(\.element)
        guard elements.allSatisfy({ $0 != "X" && BuildingProject.elements.contains($0) }) else {
            throw ParseError.malformed("Remove dummy sites and use real element symbols before adding \(name).")
        }
        self.name = name
        self.xyz = xyz
        self.elements = elements
        self.charge = charge
        self.multiplicity = multiplicity
    }

    var metalRows: [Int] { elements.indices.filter { ElementTable.isMetal(elements[$0]) }.map { $0 + 1 } }
}

struct MechanismCore {
    let geometry: MechanismGeometry
    var anchor: Int
    var placements = 8

    init(geometry: MechanismGeometry) throws {
        guard let anchor = geometry.metalRows.first else {
            throw ParseError.malformed("A reduced ChemRefine core requires a metal anchor. Use a complete product XYZ or SMILES for a metal-free stage.")
        }
        self.geometry = geometry
        self.anchor = anchor
    }
}

struct MechanismStageDraft: Identifiable {
    let id = UUID()
    var name: String
    var charge = "0"
    var multiplicity = "1"
    var substrates: [MechanismGeometry] = []
    var reagents: [MechanismGeometry] = []
    var carry: UUID?
    var selector = CarrySelector.whole
    var selectSMILES = ""
    var selectIndex = ""
    var initialCore: MechanismCore?
    var productCore: MechanismCore?
    var productXYZ: MechanismGeometry?
    var productSMILES = ""
    var productKind = ProductKind.core
    var expanded = true
    var section = Section.structures
    var calculationBranch = MechanismBranch.reactant
    var reactantSteps: [MechanismCalculation] = []
    var productSteps: [MechanismCalculation] = []
    var scoringSteps = [MechanismCalculation(.scoring)]
    var tsSteps = [MechanismCalculation(.ts)]
    var guesser = "idpp"
    var images = 9
    var guesserTimeout = 600
    var settingsYAML = ""
    var reactantYAML = ""
    var productYAML = ""
    var guesserYAML = ""

    enum Section: String, CaseIterable {
        case structures = "Structures", calculations = "Calculations"
    }

    enum CarrySelector: String, CaseIterable, Identifiable {
        case whole = "Single product", metal = "Metal complex", smiles = "Match SMILES"
        var id: Self { self }
    }

    enum ProductKind: String, CaseIterable, Identifiable {
        case core = "Reduced core", xyz = "Complete XYZ", smiles = "SMILES"
        var id: Self { self }
    }
}

enum MechanismCapture: String {
    case substrate = "Substrate", reagent = "Fixed reagent", initialCore = "Initial core"
    case productCore = "Product core", productXYZ = "Product geometry"

    var isCore: Bool { self == .initialCore || self == .productCore }
}

@MainActor
final class MechanismDraft: ObservableObject {
    static let shared = MechanismDraft()
    @Published var visible = false
    @Published var choosingCatalysts = false
    @Published var catalysts: [MechanismGeometry] = []
    @Published var stages = [MechanismStageDraft(name: "stage_1")]
    @Published var pending: CaptureTarget?
    @Published var notice = ""
    @Published var savedURL: URL?
    @Published var saving = false
    @Published var cores = 1
    @Published var workers = 1
    @Published var maxVariants = 64
    @Published var maxGPUs = 0
    @Published var workflowYAML = ""
    @Published var mechanismYAML = ""
    @Published var schema: MechanismSchema?
    @Published var schemaError = ""
    private var loadingSchema = false
    @Published var forceMetalContacts = false

    func loadSchema() async {
        guard schema == nil, !loadingSchema else { return }
        loadingSchema = true
        defer { loadingSchema = false }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("chemrefine-schema")
            let data = try await WorkflowRunner.shared.bridge(action: "mechanism-schema", path: url.path)
            schema = try JSONDecoder().decode(MechanismSchema.self, from: data)
            schemaError = ""
        } catch {
            schemaError = error.localizedDescription
        }
    }

    struct CaptureTarget {
        let stage: UUID
        let kind: MechanismCapture
    }

    func addStage() {
        var number = stages.count + 1
        while stages.contains(where: { $0.name == "stage_\(number)" }) { number += 1 }
        var stage = MechanismStageDraft(name: "stage_\(number)")
        if let previous = stages.last {
            stage.carry = previous.id
            stage.charge = previous.charge
            stage.multiplicity = previous.multiplicity
        }
        for index in stages.indices { stages[index].expanded = false }
        stages.append(stage)
    }

    func removeStage(_ id: UUID) {
        stages.removeAll { $0.id == id }
        for index in stages.indices where stages[index].carry == id { stages[index].carry = nil }
    }

    func addCatalogCatalyst(_ catalog: BosTMCStore) {
        guard !catalog.selecting, let url = catalog.xyzURL else { return }
        do {
            let refcode = catalog.details["refcode"] ?? url.deletingPathExtension().lastPathComponent
            let spin = Self.catalogInteger(catalog.details["spinmult"])
            let charge = Self.catalogInteger(catalog.details["charge"]).map(String.init) ?? ""
            let name = spin.map { "\(refcode) (M=\($0))" } ?? refcode
            let xyz = try String(contentsOf: url, encoding: .utf8)
            if catalysts.contains(where: { $0.name == name && $0.xyz == xyz && $0.charge == charge }) {
                notice = "\(name) is already in the catalyst list."
                return
            }
            catalysts.append(try MechanismGeometry(name: name, xyz: xyz, charge: charge, multiplicity: spin))
            notice = "Added \(name). \(catalysts.count) catalyst alternatives."
        } catch { notice = error.localizedDescription }
    }

    private static func catalogInteger(_ value: String?) -> Int? {
        guard let value, let number = Double(value.trimmingCharacters(in: .whitespaces)) else { return nil }
        return Int(exactly: number)
    }

    func capture(_ workspace: WorkspaceStore, target: CaptureTarget, selectionOnly: Bool) {
        do {
            guard let frame = workspace.currentFrame else { throw ParseError.noGeometry }
            let selected = Set(workspace.selectedAtomIndices)
            let atoms = selectionOnly ? frame.atoms.enumerated().filter { selected.contains($0.offset) }.map(\.element) : frame.atoms
            guard !atoms.isEmpty else { throw ParseError.malformed("Select the atoms to capture, or use Capture whole structure.") }
            let name = (workspace.document?.title ?? target.kind.rawValue) + (selectionOnly ? " selection" : "")
            let xyz = XYZWriter.string(frame: MoleculeFrame(id: 0, atoms: atoms), comment: name)
            let geometry = try MechanismGeometry(name: name, xyz: xyz, charge: selectionOnly ? "" : String(workspace.charge))
            try add([geometry], to: target)
            pending = nil
            workspace.activeTab = "ChemRefine"
        } catch { notice = error.localizedDescription }
    }

    func importXYZ(to target: CaptureTarget? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xyz") ?? .plainText]
        panel.allowsMultipleSelection = target?.kind == .substrate || target?.kind == .reagent || target == nil
        panel.message = "Choose single-geometry XYZ files in ångströms."
        guard panel.runModal() == .OK else { return }
        do {
            let geometries = try panel.urls.map { url in
                try MechanismGeometry(name: url.deletingPathExtension().lastPathComponent, xyz: String(contentsOf: url, encoding: .utf8))
            }
            if let target { try add(geometries, to: target) }
            else {
                catalysts.append(contentsOf: geometries)
                notice = "Added \(geometries.count) catalyst file(s)."
            }
        } catch { notice = error.localizedDescription }
    }

    func add(_ geometries: [MechanismGeometry], to target: CaptureTarget) throws {
        guard let index = stages.firstIndex(where: { $0.id == target.stage }), let first = geometries.first else { return }
        switch target.kind {
        case .substrate: stages[index].substrates.append(contentsOf: geometries)
        case .reagent: stages[index].reagents.append(contentsOf: geometries)
        case .initialCore: stages[index].initialCore = try MechanismCore(geometry: first)
        case .productCore:
            stages[index].productCore = try MechanismCore(geometry: first)
            stages[index].productKind = .core
        case .productXYZ:
            stages[index].productXYZ = first
            stages[index].productKind = .xyz
        }
        notice = "Added \(geometries.count == 1 ? first.name : "\(geometries.count) structures")."
    }

    var variantCount: Int? {
        var count = max(catalysts.count, 1)
        for stage in stages {
            let (product, overflow) = count.multipliedReportingOverflow(by: max(stage.substrates.count, 1))
            if overflow { return nil }
            count = product
        }
        return count
    }
}
