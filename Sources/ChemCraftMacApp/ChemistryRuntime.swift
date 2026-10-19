import AppKit
import ChemCraftCore
import Foundation
import SwiftUI
import WebKit

@MainActor
final class ChemistryRuntime: ObservableObject {
    static let shared = ChemistryRuntime()
    @Published var busy = false
    @Published var status = ""
    @Published var guiURL: URL?
    @Published var workflowDirectory: URL?
    @Published var showingWorkflow = false
    private var workflowBrowser: WKWebView?
    private var workflowBrowserURL: URL?
    func webView(for url: URL) -> WKWebView {
        if workflowBrowserURL == url, let workflowBrowser { return workflowBrowser }
        let view = WKWebView(); view.load(URLRequest(url: url))
        workflowBrowser = view; workflowBrowserURL = url
        return view
    }
    private var process: Process?
    private var guiProcess: Process?
    private var previousWorkflowServers: [Process] = []
    func newWorkflow(_ workspace: WorkspaceStore) {
        if let guiProcess, guiProcess.isRunning { previousWorkflowServers.append(guiProcess) }
        guiProcess = nil; guiURL = nil; openWorkflow(workspace)
    }
    func stopWorkflowTestServer() { guiProcess?.terminate(); guiProcess = nil; guiURL = nil; showingWorkflow = false }
    private var cancelled = false
    static var root: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ChemViewer/chemistry-venv") }
    static var python: URL { root.appendingPathComponent("bin/python") }
    var installed: Bool { FileManager.default.isExecutableFile(atPath: Self.python.path) }
    func cancel() { cancelled = true; process?.terminate(); status = "Cleanup cancelled; geometry unchanged." }

    func optimize(_ workspace: WorkspaceStore, freezeSelection: Bool) {
        guard !busy, let initial = workspace.currentFrame else { return }
        guard installed else { workspace.errorMessage = "Install the chemistry runtime with bash scripts/setup-chemistry.sh in the ChemViewer repository."; return }
        let frameIndex = workspace.frameIndex
        let document = workspace.document
        let revision = workspace.geometryRevision
        let charge = workspace.charge
        let multiplicity = workspace.multiplicity
        let fixed = freezeSelection ? workspace.selectedAtomIndices : []
        busy = true; cancelled = false; status = "UFF cleanup running…"
        Task {
            defer { busy = false; process = nil }
            do {
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("ChemViewer-UFF-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: temp) }
                let input = temp.appendingPathComponent("request.json"), output = temp.appendingPathComponent("result.json"), log = temp.appendingPathComponent("run.log")
                let atoms = initial.atoms.map { ["element": $0.element, "x": $0.position.x, "y": $0.position.y, "z": $0.position.z] as [String: Any] }
                let request: [String: Any] = ["atoms": atoms, "charge": charge, "fixed": fixed, "steps": 1000]
                try JSONSerialization.data(withJSONObject: request).write(to: input)
                guard let script = ChemistryResources.bundle.url(forResource: "chemistry_bridge", withExtension: "py") else { throw ParseError.malformed("Missing chemistry bridge") }
                FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
                let handle = try FileHandle(forWritingTo: log)
                defer { try? handle.close() }
                let job = Process(); job.executableURL = Self.python; job.arguments = [script.path, input.path, output.path]
                job.standardOutput = handle; job.standardError = handle
                if cancelled { return }
                process = job; try job.run()
                let code = await Task.detached { job.waitUntilExit(); return job.terminationStatus }.value
                if cancelled { return }
                guard code == 0 else { throw ParseError.malformed((try? String(contentsOf: log, encoding: .utf8)) ?? "UFF failed") }
                let result = try JSONDecoder().decode(CleanupResult.self, from: Data(contentsOf: output))
                guard workspace.document?.title == document?.title, workspace.frameIndex == frameIndex, workspace.geometryRevision == revision, workspace.currentFrame == initial, workspace.charge == charge, workspace.multiplicity == multiplicity else {
                    status = "Geometry changed while cleanup ran; result was not applied."; return
                }
                let optimized = result.atoms.enumerated().map { Atom(id: $0.offset, element: $0.element.element, position: Vector3($0.element.x, $0.element.y, $0.element.z)) }
                guard optimized.map(\.element) == initial.atoms.map(\.element), optimized.allSatisfy({ $0.position.x.isFinite && $0.position.y.isFinite && $0.position.z.isFinite }) else { throw ParseError.malformed("Optimizer returned invalid atom order or coordinates") }
                workspace.applyBuildingProject(try BuildingProject(atoms: optimized, groups: workspace.currentGroups, selection: workspace.selectedAtomIndices, charge: workspace.charge, multiplicity: workspace.multiplicity))
                let verdict = result.converged ? "converged" : "iteration limit reached"
                status = String(format: "UFF %@: %.3f → %.3f kcal/mol. Undo available.", verdict, result.initialEnergy, result.finalEnergy)
            } catch { status = "UFF failed; geometry unchanged."; workspace.errorMessage = error.localizedDescription }
        }
    }
    private struct CleanupResult: Decodable {
        let atoms: [LibraryFragment.Coordinate]
        let initialEnergy: Double
        let finalEnergy: Double
        let converged: Bool
    }

    func openWorkflow(_ workspace: WorkspaceStore, destination: URL? = nil) {
        if let guiProcess, guiProcess.isRunning, guiURL != nil { workspace.activeTab = "ChemRefine"; return }
        guard let frame = workspace.currentFrame, !frame.atoms.isEmpty else { workspace.errorMessage = "Build or open a structure first."; return }
        guard !frame.atoms.contains(where: { $0.element == "X" }) else { workspace.errorMessage = "Remove unused X sites before creating a calculation workflow."; return }
        guard installed else { workspace.errorMessage = "Run bash scripts/setup-chemistry.sh first."; return }
        let parent: URL
        if let destination { parent = destination }
        else {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
            panel.message = "Choose where to save the local ChemRefine workflow. A new workflow folder will be created."
            guard panel.runModal() == .OK, let selected = panel.url else { return }
            parent = selected
        }
        do {
            let folder = parent.appendingPathComponent("ChemViewer-workflow-" + UUID().uuidString.prefix(8))
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("templates"), withIntermediateDirectories: true)
            try XYZWriter.string(frame: frame).write(to: folder.appendingPathComponent("seed.xyz"), atomically: true, encoding: .utf8)
            let yaml = """
            input: seed.xyz
            template_dir: templates
            output_dir: outputs
            scratch_dir: scratch
            charge: \(workspace.charge)
            multiplicity: \(workspace.multiplicity)
            max_cores: 4
            dispatch: local
            slurm_template: cpu.slurm.header
            executables:
              orca: orca
            steps:
              - step: 1
                name: cleanup
                engine: orca
                template: cleanup.inp
            """ + "\n"
            try yaml.write(to: folder.appendingPathComponent("input.yaml"), atomically: true, encoding: .utf8)
            try "! XTB2 Opt\n".write(to: folder.appendingPathComponent("templates/cleanup.inp"), atomically: true, encoding: .utf8)
            try "#!/bin/bash\n".write(to: folder.appendingPathComponent("templates/cpu.slurm.header"), atomically: true, encoding: .utf8)
            workflowDirectory = folder
            let log = folder.appendingPathComponent("gui.log")
            FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let handle = try FileHandle(forWritingTo: log)
            let job = Process(); job.executableURL = Self.root.appendingPathComponent("bin/chemrefine")
            job.arguments = ["gui", folder.appendingPathComponent("input.yaml").path, "--no-browser", "--port", "0"]
            job.currentDirectoryURL = folder; job.standardOutput = handle; job.standardError = handle
            var env = ProcessInfo.processInfo.environment
            env["PYTHONUNBUFFERED"] = "1"; env["PATH"] = Self.root.appendingPathComponent("bin").path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
            job.environment = env; try job.run(); guiProcess = job
            status = "Starting local ChemRefine…"
            Task {
                defer { try? handle.close() }
                for _ in 0..<100 {
                    let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                    if let range = text.range(of: #"http://127\.0\.0\.1:\d+/\?token=[A-Za-z0-9_-]+"#, options: .regularExpression), let url = URL(string: String(text[range])) {
                        guiURL = url; workspace.activeTab = "ChemRefine"; status = "Local ChemRefine ready. Configure engines, validate, then run."; return
                    }
                    if !job.isRunning { workspace.errorMessage = "ChemRefine could not start. See \(log.path)"; return }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                workspace.errorMessage = "ChemRefine startup timed out. See \(log.path)"
            }
        } catch { workspace.errorMessage = error.localizedDescription }
    }
}

struct LocalWorkflowView: View {
    var embedded = false
    @ObservedObject private var runtime = ChemistryRuntime.shared
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var workspace: WorkspaceStore
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ChemRefine · Local workflow").font(.headline)
                Spacer()
                if runtime.guiURL != nil {
                    Button("New workflow…") { runtime.newWorkflow(workspace) }
                    Button("Open result…", action: openResult)
                    Button("Open in browser") { if let url = runtime.guiURL { NSWorkspace.shared.open(url) } }
                }
                if !embedded { Button("Done") { dismiss() } }
            }.padding(10)
            if let url = runtime.guiURL { WorkflowWebView(url: url).id(url) }
            else {
                VStack(spacing: 16) {
                    Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 44)).foregroundStyle(.secondary)
                    Text("Build, validate and run a local workflow").font(.title2)
                    Text("Start from the current structure. The local ChemRefine editor includes workflow steps, templates, YAML, structures and run controls.")
                        .multilineTextAlignment(.center).frame(maxWidth: 540)
                    Button("Create workflow from current structure…") { runtime.openWorkflow(workspace) }
                        .buttonStyle(.borderedProminent).disabled(workspace.currentFrame?.atoms.isEmpty ?? true)
                    Text(runtime.status.isEmpty ? "Configure installed engine executables in the workflow editor." : runtime.status)
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            }
        }.frame(minWidth: embedded ? 400 : 1000, minHeight: embedded ? 300 : 700)
    }
    private func openResult() {
        let panel = NSOpenPanel(); panel.directoryURL = runtime.workflowDirectory?.appendingPathComponent("outputs")
        panel.message = "Open a computed XYZ or calculation output in ChemViewer."
        if panel.runModal() == .OK, let url = panel.url {
            workspace.open(url); workspace.activeTab = "Image"
            if !embedded { dismiss() }
        }
    }
}
private struct WorkflowWebView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView { ChemistryRuntime.shared.webView(for: url) }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
