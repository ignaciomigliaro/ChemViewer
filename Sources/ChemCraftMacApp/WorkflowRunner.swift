import AppKit
import ChemCraftCore
import Darwin
import SwiftUI

@MainActor
final class WorkflowRunner: ObservableObject {
    static let shared = WorkflowRunner()
    struct Check: Decodable, Identifiable {
        let name: String
        let status: String
        let detail: String
        var id: String { name + detail }
    }
    struct Report: Decodable {
        let ok: Bool
        let checks: [Check]
        let requiredBackends: [String]
        let missingBackends: [String]
    }
    struct Response: Decodable {
        let started: Bool?
        let report: Report?
        let pid: Int?
        let log: String?
    }
    struct RunStatus: Decodable {
        struct Step: Decodable { let cached: Bool; let failures: Int; let reported_survivors: Int }
        let running: Bool
        let steps: [Step]
        let log: String?
        let log_tail: [String]?
    }
    @Published var orcaPath: String = UserDefaults.standard.string(forKey: "ChemViewerORCAExecutable") ?? "" {
        didSet { UserDefaults.standard.set(orcaPath, forKey: "ChemViewerORCAExecutable") }
    }
    @Published var umaPython: String = UserDefaults.standard.string(forKey: "ChemViewerUMAPython") ?? "" {
        didSet { UserDefaults.standard.set(umaPython, forKey: "ChemViewerUMAPython") }
    }
    @Published private(set) var pythonStatus = "Default fills missing UMA step paths; each step can override it below."
    @Published private(set) var report: Report?
    @Published private(set) var busy = false
    @Published private(set) var currentAction = ""
    private var driverPID: Int?
    private var launchedAt = Date()
    @Published private(set) var running = false
    @Published private(set) var status = "Check the workflow, then run it locally."
    @Published private(set) var logText = ""
    @Published private(set) var logPath: String?
    @Published private(set) var runConfigPath: String?
    private var preparationProcess: Process?
    private var monitoring: Task<Void, Never>?
    private var generation = 0
    private init() {
        if let path = UserDefaults.standard.string(forKey: "ChemViewerLastRunConfig"), FileManager.default.fileExists(atPath: path) {
            runConfigPath = path; driverPID = UserDefaults.standard.integer(forKey: "ChemViewerLastRunPID")
            running = true; launchedAt = .distantPast; status = "Reconnecting to the last ChemRefine run…"; startMonitoring(path)
        }
    }
    func chooseORCA() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.canChooseFiles = true
        panel.message = "Choose the orca executable inside the complete macOS ORCA installation."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path) else { status = "Choose an executable file, not an installer/archive."; return }
        orcaPath = url.path; status = "ORCA selected. Check the workflow to verify its installation."
    }
    var resolvedUMAPython: String {
        let path = (umaPython.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).expandingTildeInPath
        guard !path.isEmpty else { return "" }
        var directory: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &directory)
        return directory.boolValue ? URL(fileURLWithPath: path).appendingPathComponent("bin/python").path : path
    }
    func chooseUMAPython() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.message = "Choose the UMA environment folder or its bin/python executable."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var directory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
        let candidate = directory.boolValue ? url.appendingPathComponent("bin/python") : url
        guard FileManager.default.isExecutableFile(atPath: candidate.path) else { pythonStatus = "Choose an environment containing bin/python, or an executable Python interpreter."; return }
        // Preserve the environment's symlink path: resolving it can select the base Python.
        umaPython = candidate.path; pythonStatus = "Python selected. Check Python to verify imports, or Use for UMA steps to update this workflow."
    }
    func checkUMAPython() {
        guard !busy, !running else { return }
        busy = true; currentAction = "check-python"; pythonStatus = "Checking the selected Python and installed packages…"
        Task {
            defer { busy = false; preparationProcess = nil }
            do {
                let path = ChemistryRuntime.shared.workflowDirectory?.appendingPathComponent("input.yaml").path ?? FileManager.default.temporaryDirectory.appendingPathComponent("input.yaml").path
                let data = try await bridge(action: "check-python", path: path, trackPreparation: true, pythonPath: resolvedUMAPython)
                let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                pythonStatus = result["detail"] as? String ?? "Python checked."
            } catch { pythonStatus = error.localizedDescription }
        }
    }
    func applyUMAPython() {
        guard !busy, !running else { return }
        guard !umaPython.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { pythonStatus = "Choose a Python environment first. Clear individual step fields to use managed backends."; return }
        busy = true; currentAction = "apply-python"
        Task {
            defer { busy = false }
            do {
                let count = try await ChemistryRuntime.shared.applyUMAPython(resolvedUMAPython, overwrite: true)
                _ = try await ChemistryRuntime.shared.saveWorkflowEditor(orcaPath: orcaPath, umaPython: resolvedUMAPython)
                pythonStatus = "Saved Python environment for \(count) UMA step(s) in this workflow."
            } catch { pythonStatus = error.localizedDescription }
        }
    }
    static let launchActions: Set<String> = ["run", "resume", "rebuild-cache", "rebuild-nms", "rerun", "rerun-errors"]
    func perform(_ action: String) {
        guard !busy, !running else { return }
        currentAction = action; busy = true; generation += 1; let request = generation
        status = Self.launchActions.contains(action) ? "Saving editor and checking files, engines and selected models…" : action == "install" ? "Installing only the workflow's missing backend environments…" : "Saving editor and checking workflow…"
        Task {
            defer { if generation == request { busy = false; preparationProcess = nil } }
            do {
                let path = try await ChemistryRuntime.shared.saveWorkflowEditor(orcaPath: orcaPath, umaPython: resolvedUMAPython)
                guard request == generation else { return }
                try await execute(action: action, configPath: path, generation: request)
            } catch { if request == generation { status = error.localizedDescription } }
        }
    }
    /// Native acceptance also uses the exact process/API path, without a file dialog.
    @discardableResult
    func execute(action: String, configPath: String, generation request: Int? = nil, target: String? = nil) async throws -> Data {
        let data = try await bridge(action: action, path: configPath, trackPreparation: true, target: target)
        if let request, request != generation { return data }
        if Self.launchActions.contains(action) {
            let response = try JSONDecoder().decode(Response.self, from: data)
            report = response.report
            guard response.started == true else { status = "Workflow not started. Resolve the items marked red, then run again."; return data }
            running = true; runConfigPath = configPath; logPath = response.log
            driverPID = response.pid; launchedAt = Date()
            UserDefaults.standard.set(configPath, forKey: "ChemViewerLastRunConfig")
            UserDefaults.standard.set(response.pid, forKey: "ChemViewerLastRunPID")
            status = "ChemRefine \(action) started (PID \(response.pid ?? 0)). It continues if this window closes."
            logText = ""; startMonitoring(configPath)
        } else if action == "scaffold" {
            report = try JSONDecoder().decode(Response.self, from: data).report
            status = "Created missing templates without replacing existing files. Review them before running."
        } else {
            report = try JSONDecoder().decode(Report.self, from: data)
            status = report?.ok == true ? "Workflow files and declared engines are ready. Run verifies selected MLIP weights before launching." : "Workflow needs the items marked red before it can run."
        }
        return data
    }
    /// The embedded dashboard uses the same saved-editor/preflight/monitoring path.
    func launchFromEditor(action: String, target: String?) async throws -> Data {
        guard Self.launchActions.contains(action) else { throw ParseError.malformed("Unknown workflow action.") }
        guard !busy, !running else { throw ParseError.malformed("A workflow is already running or being prepared.") }
        busy = true; currentAction = action; generation += 1
        defer { busy = false; preparationProcess = nil }
        status = "Saving editor and preparing ChemRefine \(action)…"
        do {
            let path = try await ChemistryRuntime.shared.saveWorkflowEditor(orcaPath: orcaPath, umaPython: resolvedUMAPython)
            return try await execute(action: action, configPath: path, generation: generation, target: target)
        } catch {
            status = error.localizedDescription; throw error
        }
    }
    func cancelPreparation() {
        guard !Self.launchActions.contains(currentAction) else { return }
        generation += 1
        preparationProcess?.terminate(); preparationProcess = nil; busy = false
        status = "Preparation cancelled. No new workflow was launched."
    }
    private func startMonitoring(_ config: String) {
        monitoring?.cancel()
        monitoring = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            while !Task.isCancelled {
                do {
                    let state = try await readStatus(config)
                    guard !Task.isCancelled, runConfigPath == config else { return }
                    logPath = state.log; logText = (state.log_tail ?? []).joined(separator: "\n")
                    if !state.running {
                        if logText.contains("pipeline finished after") {
                            let failures = state.steps.reduce(0) { $0 + $1.failures }
                            status = failures == 0 && state.steps.allSatisfy({ $0.cached && $0.reported_survivors > 0 }) ? "ChemRefine completed. Open result to inspect the calculated structures." : "ChemRefine finished with failed or empty steps. Inspect the run log."
                            running = false; return
                        }
                        let driverExited = driverPID.map { value in guard let pid = Int32(exactly: value), pid > 0 else { return true }; return kill(pid, 0) != 0 && errno == ESRCH } ?? true
                        if driverExited && Date().timeIntervalSince(launchedAt) > 3 {
                            status = "ChemRefine driver stopped. Check the log and results before using them."; running = false; return
                        }
                        if logText.contains("ERROR") || logText.contains("Traceback") || logText.contains("Error:") {
                            status = "ChemRefine stopped with an error. Inspect the run log."; running = false; return
                        }
                    }
                } catch { status = "Could not refresh run status: " + error.localizedDescription }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
    func readStatus(_ path: String) async throws -> RunStatus {
        let data = try await bridge(action: "status", path: path)
        return try JSONDecoder().decode(RunStatus.self, from: data)
    }
    func bridge(action: String, path: String, trackPreparation: Bool = false, target: String? = nil, pythonPath: String? = nil) async throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ChemViewer-Workflow-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("request.json"), output = directory.appendingPathComponent("result.json"), log = directory.appendingPathComponent("bridge.log")
        var payload: [String: Any] = ["action": action, "config_path": path]
        if let target, !target.isEmpty { payload["target"] = target }
        if let pythonPath { payload["python_path"] = pythonPath }
        try JSONSerialization.data(withJSONObject: payload).write(to: input)
        guard let script = ChemistryResources.bundle.url(forResource: "workflow_bridge", withExtension: "py") else { throw ParseError.malformed("Missing ChemRefine execution bridge.") }
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
        let process = Process(); process.executableURL = ChemistryRuntime.python
        process.arguments = [script.path, input.path, output.path]; process.currentDirectoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        process.standardOutput = handle; process.standardError = handle
        var env = ProcessInfo.processInfo.environment
        let orcaDirectory = orcaPath.isEmpty ? "" : URL(fileURLWithPath: orcaPath).deletingLastPathComponent().path + ":"
        if !orcaPath.isEmpty { env["ORCADIR"] = URL(fileURLWithPath: orcaPath).deletingLastPathComponent().path }
        env["PATH"] = orcaDirectory + ChemistryRuntime.root.appendingPathComponent("bin").path + ":/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        env["PYTHONUNBUFFERED"] = "1"; env["OMP_NUM_THREADS"] = "1"
        process.environment = env
        if trackPreparation { preparationProcess = process }
        try process.run()
        let code = await Task.detached { process.waitUntilExit(); return process.terminationStatus }.value
        guard code == 0 else {
            let details = ((try? String(contentsOf: log, encoding: .utf8)) ?? "").suffix(12000)
            throw ParseError.malformed(details.isEmpty ? "ChemRefine preparation failed." : String(details))
        }
        return try Data(contentsOf: output)
    }
    func openLog() { if let logPath { NSWorkspace.shared.open(URL(fileURLWithPath: logPath)) } }
}

struct WorkflowExecutionPanel: View {
    @ObservedObject private var runner = WorkflowRunner.shared
    @State private var showChecks = false
    @State private var showLog = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button("Run ChemRefine") { runner.perform("run") }.buttonStyle(.borderedProminent).disabled(runner.busy || runner.running)
                    Button("Resume") { runner.perform("resume") }.disabled(runner.busy || runner.running)
                    Button("Check workflow") { showChecks = true; runner.perform("check") }.disabled(runner.busy || runner.running)
                    Button("Create missing templates") { showChecks = true; runner.perform("scaffold") }.disabled(runner.busy || runner.running)
                    Button("Install required backends") { showChecks = true; runner.perform("install") }.disabled(runner.busy || runner.running || (runner.report?.missingBackends.isEmpty ?? true))
                    Button("Choose ORCA…") { runner.chooseORCA() }.disabled(runner.busy || runner.running)
                    Link("Get ORCA", destination: URL(string: "https://www.faccts.de/docs/orca/6.1/tutorials/first_steps/install.html")!)
                    if runner.busy {
                        ProgressView().controlSize(.small)
                        if !WorkflowRunner.launchActions.contains(runner.currentAction) { Button("Cancel preparation") { runner.cancelPreparation() } }
                    }
                }
            }
            HStack {
                Text("UMA Python").font(.caption.bold())
                TextField("Automatic — ChemRefine-managed backend", text: $runner.umaPython)
                    .textFieldStyle(.roundedBorder).font(.caption.monospaced())
                    .disabled(runner.busy || runner.running)
                Button("Choose environment…") { runner.chooseUMAPython() }.disabled(runner.busy || runner.running)
                Button("Check Python") { runner.checkUMAPython() }.disabled(runner.busy || runner.running || runner.umaPython.isEmpty)
                Button("Use for UMA steps") { runner.applyUMAPython() }.disabled(runner.busy || runner.running || runner.umaPython.isEmpty)
            }
            Text(runner.pythonStatus).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text(runner.status).font(.caption).textSelection(.enabled)
            if let report = runner.report {
                DisclosureGroup("Readiness · \(report.checks.filter { $0.status == "error" }.count) blocking item(s)", isExpanded: $showChecks) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(report.checks.enumerated()), id: \.offset) { _, check in
                                HStack(alignment: .top) {
                                    Image(systemName: check.status == "ok" ? "checkmark.circle.fill" : check.status == "error" ? "xmark.circle.fill" : "info.circle").foregroundStyle(check.status == "ok" ? Color.green : check.status == "error" ? .red : .orange)
                                    Text(check.name + ": " + check.detail).font(.caption).textSelection(.enabled)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 135)
                }
            }
            if let path = runner.runConfigPath {
                HStack {
                    Text("Run: " + path).font(.caption).lineLimit(2).textSelection(.enabled)
                    Button("Open run folder") { NSWorkspace.shared.open(URL(fileURLWithPath: path).deletingLastPathComponent()) }
                }
            }
            if runner.logPath != nil {
                DisclosureGroup("Run log", isExpanded: $showLog) {
                    ScrollView { Text(runner.logText).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 100)
                    Button("Open full log") { runner.openLog() }
                }
            }
        }.padding(.horizontal, 10).padding(.bottom, 8)
    }
}
