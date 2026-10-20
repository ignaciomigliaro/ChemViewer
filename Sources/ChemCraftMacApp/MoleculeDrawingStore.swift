import AppKit
import ChemCraftCore
import SwiftUI
import UniformTypeIdentifiers

enum DrawingTool: String, CaseIterable {
    case chain = "Chain", bond = "Bond", atom = "Atom", ring = "Ring", move = "Move", erase = "Erase", positive = "+ charge", negative = "− charge"
}

@MainActor
final class MoleculeDrawingStore: ObservableObject {
    @Published private(set) var graph = MolecularSketch()
    @Published var tool: DrawingTool = .bond
    @Published var element = "C"
    @Published var order = 1
    @Published var stereo = "none"
    @Published var ringSize = 6
    @Published var aromatic = true
    @Published var ringTemplate: SketchRingTemplate? = .benzene
    @Published var showElements = false
    @Published var selectedID: Int?
    @Published var smilesInput = ""
    @Published var autoPreview = true { didSet { schedulePreview() } }
    @Published private(set) var busy = false
    @Published private(set) var status = "Draw a bond, place atoms, or add a ring."
    @Published private(set) var preview: DrawingResult?
    @Published private(set) var revision = 0
    @Published private(set) var fitRevision = 0
    @Published private var undoStack: [MolecularSketch] = []
    @Published private var redoStack: [MolecularSketch] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    private var previewRevision = -1
    var previewIsCurrent: Bool { preview != nil && previewRevision == revision }
    private var debounce: Task<Void, Never>?
    private var process: Process?
    private var generation = 0

    struct DrawingResult: Decodable {
        let graph: MolecularSketch
        let smiles: String
        let atoms: [LibraryFragment.Coordinate]?
        let formula: String?
        let charge: Int?
        let optimized: Bool?
        let converged: Bool?
        let molBlock: String?
        let radicalElectrons: Int?
        var frame: MoleculeFrame? {
            guard let atoms else { return nil }
            return MoleculeFrame(id: 0, atoms: atoms.enumerated().map { Atom(id: $0.offset, element: $0.element.element, position: Vector3($0.element.x, $0.element.y, $0.element.z)) }, comment: "Draw → RDKit ETKDG 3D conformer")
        }
    }
    func commit(_ next: MolecularSketch) {
        do { try next.validate() } catch { status = error.localizedDescription; return }
        guard next != graph else { return }
        undoStack.append(graph); if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack = []; cancel(); graph = next; revision += 1
        status = "Drawing changed; generate 3D to update the preview."
        schedulePreview()
    }
    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(graph); cancel(); graph = previous; revision += 1; schedulePreview()
    }
    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(graph); cancel(); graph = next; revision += 1; schedulePreview()
    }
    func fit() { fitRevision += 1 }
    func cancel() {
        if busy { status = "3D generation cancelled; drawing unchanged." }
        generation += 1; debounce?.cancel(); debounce = nil
        if let process, process.isRunning { process.terminate() }
        process = nil; busy = false
    }
    private func schedulePreview() {
        debounce?.cancel()
        guard autoPreview, !graph.atoms.isEmpty else { return }
        debounce = Task {
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }; generate3D()
        }
    }
    func generate3D() { run(operation: "generate") }
    func clean2D() { run(operation: "depict") }
    func importSMILES() { run(operation: "depict", smiles: smilesInput) }
    private func run(operation: String, smiles: String? = nil) {
        guard ChemistryRuntime.shared.installed else { status = "Install the local RDKit runtime: bash scripts/setup-chemistry.sh"; return }
        guard smiles != nil || !graph.atoms.isEmpty else { status = "Draw a structure first."; return }
        cancel(); generation += 1
        let requestID = generation, sourceRevision = revision, sourceGraph = graph
        busy = true; status = operation == "depict" ? "Preparing 2D structure…" : "Generating 3D conformer locally…"
        Task {
            guard requestID == generation else { return }
            defer { if requestID == generation { busy = false; process = nil } }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ChemViewer-Draw-" + UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: directory) }
                struct Request: Encodable { let operation: String; let graph: MolecularSketch; let smiles: String? }
                let input = directory.appendingPathComponent("input.json"), output = directory.appendingPathComponent("result.json"), log = directory.appendingPathComponent("run.log")
                try JSONEncoder().encode(Request(operation: operation, graph: sourceGraph, smiles: smiles)).write(to: input)
                guard let script = ChemistryResources.bundle.url(forResource: "drawing_bridge", withExtension: "py") else { throw ParseError.malformed("Missing drawing runtime bridge.") }
                FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
                let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
                let job = Process(); job.executableURL = ChemistryRuntime.python
                job.arguments = [script.path, input.path, output.path]; job.standardOutput = handle; job.standardError = handle
                process = job; try job.run()
                let timeout = Task { try? await Task.sleep(nanoseconds: 45_000_000_000); if !Task.isCancelled && job.isRunning { job.terminate() } }
                defer { timeout.cancel() }
                let code = await Task.detached { job.waitUntilExit(); return job.terminationStatus }.value
                guard requestID == generation, revision == sourceRevision else { return }
                guard code == 0 else {
                    let details = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    throw ParseError.malformed(details.isEmpty ? "3D generation timed out or could not complete." : details)
                }
                let result = try JSONDecoder().decode(DrawingResult.self, from: Data(contentsOf: output))
                try result.graph.validate()
                if operation == "depict" {
                    commit(result.graph); fit(); status = "2D structure ready. Generate 3D or continue drawing."
                } else {
                    guard let frame = result.frame, !frame.atoms.isEmpty, frame.atoms.allSatisfy({ $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite }) else { throw ParseError.malformed("Invalid 3D coordinates returned by RDKit.") }
                    preview = result; previewRevision = revision
                    let cleanup = result.optimized == true ? (result.converged == true ? "UFF converged" : "UFF iteration limit") : "UFF parameters unavailable; embedded geometry"
                    status = "\(result.formula ?? "") · \(cleanup). 3D conformer ready."
                }
            } catch { if requestID == generation { status = "Could not build structure: " + error.localizedDescription } }
        }
    }
    func use3D(in workspace: WorkspaceStore, multiplicity: Int) {
        guard previewIsCurrent, let result = preview, let frame = result.frame else { return }
        do {
            workspace.clearSelection()
            workspace.applyBuildingProject(try BuildingProject(atoms: frame.atoms, charge: result.charge ?? 0, multiplicity: multiplicity), remapMeasurements: true)
            workspace.activeTab = "Image"
        } catch { workspace.errorMessage = error.localizedDescription }
    }
    func saveDrawing() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "drawing.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(graph).write(to: url, options: .atomic) }
        catch { status = error.localizedDescription }
    }
    func openDrawing() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size < 2_000_000 else { throw ParseError.malformed("Drawing file exceeds 2 MB.") }
            let next = try JSONDecoder().decode(MolecularSketch.self, from: Data(contentsOf: url)); try next.validate(); commit(next); fit()
        } catch { status = error.localizedDescription }
    }
}
