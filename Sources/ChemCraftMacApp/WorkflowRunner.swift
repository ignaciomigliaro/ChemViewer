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
    func perform(_ action: String) {
        guard !busy, !running else { return }
        currentAction = action; busy = true; generation += 1; let request = generation
        status = action == "run" ? "Saving editor and checking files, engines and selected models…" : action == "install" ? "Installing only the workflow's missing backend environments…" : "Saving editor and checking workflow…"
        Task {
            defer { if generation == request { busy = false; preparationProcess = nil } }
            do {
                let path = try await ChemistryRuntime.shared.saveWorkflowEditor(orcaPath: orcaPath)
                guard request == generation else { return }
                try await execute(action: action, configPath: path, generation: request)
            } catch { if request == generation { status = error.localizedDescription } }
        }
    }
    /// Native acceptance also uses the exact process/API path, without a file dialog.
    func execute(action: String, configPath: String, generation request: Int? = nil) async throws {
        let data = try await bridge(action: action, path: configPath, trackPreparation: true)
        if let request, request != generation { return }
        if action == "run" {
            let response = try JSONDecoder().decode(Response.self, from: data)
            report = response.report
            guard response.started == true else { status = "Workflow not started. Resolve the items marked red, then run again."; return }
            running = true; runConfigPath = configPath; logPath = response.log
            driverPID = response.pid; launchedAt = Date()
            UserDefaults.standard.set(configPath, forKey: "ChemViewerLastRunConfig")
            UserDefaults.standard.set(response.pid, forKey: "ChemViewerLastRunPID")
            status = "ChemRefine started (PID \(response.pid ?? 0)). It continues if this window closes."
            logText = ""; startMonitoring(configPath)
        } else if action == "scaffold" {
            report = try JSONDecoder().decode(Response.self, from: data).report
            status = "Created missing templates without replacing existing files. Review them before running."
        } else {
            report = try JSONDecoder().decode(Report.self, from: data)
            status = report?.ok == true ? "Workflow files and declared engines are ready. Run verifies selected MLIP weights before launching." : "Workflow needs the items marked red before it can run."
        }
    }
    func cancelPreparation() {
        guard currentAction != "run" else { return }
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
    func bridge(action: String, path: String, trackPreparation: Bool = false) async throws -> Data {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ChemViewer-Workflow-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("request.json"), output = directory.appendingPathComponent("result.json"), log = directory.appendingPathComponent("bridge.log")
        try JSONSerialization.data(withJSONObject: ["action": action, "config_path": path]).write(to: input)
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
                    Button("Check workflow") { showChecks = true; runner.perform("check") }.disabled(runner.busy || runner.running)
                    Button("Create missing templates") { showChecks = true; runner.perform("scaffold") }.disabled(runner.busy || runner.running)
                    Button("Install required backends") { showChecks = true; runner.perform("install") }.disabled(runner.busy || runner.running || (runner.report?.missingBackends.isEmpty ?? true))
                    Button("Choose ORCA…") { runner.chooseORCA() }.disabled(runner.busy || runner.running)
                    Link("Get ORCA", destination: URL(string: "https://www.faccts.de/docs/orca/6.1/tutorials/first_steps/install.html")!)
                    if runner.busy {
                        ProgressView().controlSize(.small)
                        if runner.currentAction != "run" { Button("Cancel preparation") { runner.cancelPreparation() } }
                    }
                }
            }
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
