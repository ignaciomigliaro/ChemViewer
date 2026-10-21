import AppKit
import CryptoKit
import ChemCraftCore
import Foundation
import SwiftUI

/// Profiles contain connection settings only. Authentication stays with OpenSSH/Terminal.
struct RemoteProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "New connection"
    var host = ""
    var directory = "~"
    var python = "python3"
    var setup = ""
    var config = ""
}

@MainActor
final class RemoteConnection: ObservableObject {
    static let shared = RemoteConnection()
    @Published var workflowRemoteSelected = false
    var isConnected: Bool { session != nil && !sessionKey.isEmpty }
    @Published var presented = false
    @Published var explorerVisible = UserDefaults.standard.bool(forKey: "ChemViewerRemoteExplorerVisible") {
        didSet { UserDefaults.standard.set(explorerVisible, forKey: "ChemViewerRemoteExplorerVisible") }
    }
    enum ExplorerOrder: String, CaseIterable { case name = "Name", fileExtension = "Extension" }
    @Published var explorerOrder = ExplorerOrder(rawValue: UserDefaults.standard.string(forKey: "ChemViewerRemoteExplorerOrder") ?? "") ?? .name {
        didSet { UserDefaults.standard.set(explorerOrder.rawValue, forKey: "ChemViewerRemoteExplorerOrder") }
    }
    func sortedExplorerEntries(_ path: String) -> [Entry] {
        (explorerNodes[path] ?? []).sorted {
            if $0.directory != $1.directory { return $0.directory }
            if explorerOrder == .fileExtension && !$0.directory {
                let a = URL(fileURLWithPath: $0.name).pathExtension.lowercased()
                let b = URL(fileURLWithPath: $1.name).pathExtension.lowercased()
                if a != b { return a < b }
            }
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.path < $1.path : comparison == .orderedAscending
        }
    }
    private var folderNavigation = 0
    func enterExplorerFolder(_ path: String) {
        folderNavigation += 1; let navigation = folderNavigation
        if !busy { loadExplorerFolder(path, makeRoot: true); return }
        let identity = explorerIdentity, cancellation = explorerCancellation
        Task {
            while busy { do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return } }
            guard navigation == folderNavigation, identity == explorerIdentity, cancellation == explorerCancellation else { return }
            loadExplorerFolder(path, makeRoot: true)
        }
    }
    @Published var explorerRoot = ""
    @Published var explorerNodes: [String:[Entry]] = [:]
    @Published var expandedExplorerPaths: Set<String> = []
    func clearExplorer() { explorerCancellation += 1; explorerRoot = ""; explorerNodes = [:]; expandedExplorerPaths = [] }
    func toggleExplorerFolder(_ path: String, expanded: Bool) {
        if expanded {
            expandedExplorerPaths.insert(path)
            if explorerNodes[path] == nil {
                if !busy { loadExplorerFolder(path) }
                else {
                    let host = profile.host, cancellation = explorerCancellation
                    Task {
                        while busy { do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return } }
                        guard explorerCancellation == cancellation, profile.host == host, expandedExplorerPaths.contains(path), explorerNodes[path] == nil else { return }
                        loadExplorerFolder(path)
                    }
                }
            }
        } else { expandedExplorerPaths.remove(path) }
    }
    func loadExplorerFolder(_ path: String, makeRoot: Bool = false, refresh: Bool = false) {
        guard !busy else { return }; busy = true; serial += 1; let token = serial
        let snapshot = profile
        Task {
            defer { if token == serial { busy = false } }
            do {
                let result = try await request(["action":"list", "path":path, "refresh":refresh], profile: snapshot)
                guard token == serial else { return }
                let entries = try JSONDecoder().decode([Entry].self, from: JSONSerialization.data(withJSONObject: result["entries"] ?? []))
                let canonical = result["path"] as? String ?? path
                explorerNodes[path] = entries; explorerNodes[canonical] = entries
                if makeRoot || explorerRoot.isEmpty { explorerRoot = canonical; profile.directory = canonical; saveProfile() }
                explorerVisible = true; status = "\(entries.count) entries · \(snapshot.host)"
            } catch { if token == serial { status = error.localizedDescription } }
        }
    }
    var explorerIdentity: String { profile.id.uuidString + "\0" + profile.host + "\0" + profile.python + "\0" + profile.setup }
    /// One load per visible sidebar/connection identity. Wait for authentication or another request.
    func ensureExplorerLoaded() async {
        do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
        let identity = explorerIdentity
        while busy {
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
            guard identity == explorerIdentity else { return }
        }
        guard !Task.isCancelled, identity == explorerIdentity, !profile.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              explorerRoot.isEmpty || explorerNodes[explorerRoot] == nil else { return }
        loadExplorerFolder(explorerRoot.isEmpty ? profile.directory : explorerRoot, makeRoot: true)
    }
    @Published var profile = RemoteProfile() {
        didSet {
            if oldValue.host != profile.host || oldValue.python != profile.python || oldValue.setup != profile.setup {
                RemoteWorkflowRuntime.shared.stop(); disconnect(); clearExplorer(); entries = []; selected = nil; editingPath = ""
            }
        }
    }
    @Published var profiles: [RemoteProfile] = []
    @Published var busy = false
    @Published var autoRefresh = false
    @Published var entries: [Entry] = []
    @Published var selected: String?
    @Published var status = "Enter an SSH alias, authenticate, then browse."
    @Published var log = ""
    @Published var editingPath = ""
    @Published var editor = ""
    @Published var editorHash = ""
    private var editingHost = ""
    @Published var runSummary = ""
    @Published var lastOpened: String?
    @Published var lastOpenedHost: String?
    @Published var connectionStatus = "Disconnected · authenticate once, then browse"
    @Published var parentDirectory = "~"
    private var session: RemoteSSHSession?
    private var sessionKey = ""
    private var cachedFolders: [String: (Date, [String: Any])] = [:]
    private var channelBusy = false
    private var process: Process?
    private var serial = 0
    private var explorerCancellation = 0
    struct Entry: Identifiable, Decodable {
        var id: String { path }
        let name: String
        let path: String
        let directory: Bool
        let size: Int64
        var isMolecularFile: Bool { ["xyz", "out", "log", "inp", "in", "cvproject", "mvproject"].contains(URL(fileURLWithPath: name).pathExtension.lowercased()) }
    }
    private let makeSession: ([String]) throws -> RemoteSSHSession
    init(makeSession: @escaping ([String]) throws -> RemoteSSHSession = { try RemoteSSHSession(arguments: $0) }) {
        self.makeSession = makeSession
        if let data = UserDefaults.standard.data(forKey: "ChemViewerSSHProfiles"), let saved = try? JSONDecoder().decode([RemoteProfile].self, from: data) {
            profiles = saved; if let first = saved.first { profile = first }
        }
    }
    func saveProfile() {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = profile }
        else { profiles.append(profile) }
        if let data = try? JSONEncoder().encode(profiles) { UserDefaults.standard.set(data, forKey: "ChemViewerSSHProfiles") }
    }
    func selectProfile(_ id: UUID) {
        guard !busy, let saved = profiles.first(where: { $0.id == id }) else { return }
        clearExplorer(); profile = saved; entries = []; selected = nil; editingPath = ""; editor = ""; runSummary = ""; log = ""
    }
    func disconnect() { explorerCancellation += 1; session?.close(); session = nil; sessionKey = ""; cachedFolders = [:]; connectionStatus = "Disconnected" }
    func cancel() { serial += 1; disconnect(); process?.terminate(); process = nil; busy = false; status = "Request cancelled. A remote job already submitted continues on the cluster; refresh its status." }
    func perform(_ action: String, path: String? = nil, workspace: WorkspaceStore? = nil, folder: String? = nil, refresh: Bool = false, reloadExisting: Bool = false) {
        guard !busy else { return }
        if action == "write", editingHost != profile.host { status = "Reopen the text file after changing hosts."; return }
        saveProfile(); busy = true; serial += 1; let token = serial
        let snapshot = profile
        status = action == "run" || action == "resume" ? "Checking and submitting on \(snapshot.host)…" : "\(action.capitalized) · \(snapshot.host)…"
        var payload: [String: Any] = ["action": action, "path": path ?? snapshot.directory]
        if refresh { payload["refresh"] = true }
        if action == "write" { payload["data"] = Data(editor.utf8).base64EncodedString(); payload["sha256"] = editorHash }
        Task {
            defer { if token == serial { busy = false; process = nil } }
            do {
                let result = try await request(payload, profile: snapshot, edit: action == "edit", folder: folder)
                guard token == serial else { return }
                switch action {
                case "authenticate":
                    if let path = result["terminal"] as? String {
                        let opener = Process(); opener.executableURL = URL(fileURLWithPath: "/usr/bin/open"); opener.arguments = ["-a", "Terminal", path]; try opener.run()
                    }
                    status = "Complete SSH authentication in Terminal, then click Browse. The connection can be reused for 8 hours."
                case "info":
                    status = "Remote Python: \(result["python"] ?? "") · ChemRefine \(result["chemrefine"] ?? "")"
                    log = String(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8) ?? ""
                case "list":
                    entries = try JSONDecoder().decode([Entry].self, from: JSONSerialization.data(withJSONObject: result["entries"] ?? []))
                    explorerVisible = true
                    if explorerRoot.isEmpty { explorerRoot = result["path"] as? String ?? snapshot.directory }
                    explorerNodes[result["path"] as? String ?? snapshot.directory] = entries
                    parentDirectory = result["parent"] as? String ?? "~"
                    profile.directory = result["path"] as? String ?? snapshot.directory; selected = nil; saveProfile()
                    status = "\(entries.count) entries · \(snapshot.host)" + (result["_cached"] as? Bool == true ? " · cached (Refresh folder for changes)" : "")
                case "read":
                    if let local = result["local"] as? String, let workspace {
                        lastOpened = result["path"] as? String; lastOpenedHost = snapshot.host
                        let url = URL(fileURLWithPath: local)
                        var companions: [String:URL] = [:]
                        if ["inp", "in"].contains(url.pathExtension.lowercased()) {
                            let text = try String(contentsOf: url, encoding: .utf8)
                            for reference in Set(ORCAInputParser.externalXYZReferences(in: text)) {
                                let base = URL(fileURLWithPath: (result["path"] as? String ?? path ?? "")).deletingLastPathComponent()
                                let remotePath = reference.hasPrefix("/") || reference.hasPrefix("~") ? reference : URL(fileURLWithPath: reference, relativeTo: base).standardizedFileURL.path
                                let companion = try await request(["action":"read", "path":remotePath], profile: snapshot)
                                if let local = companion["local"] as? String { companions[reference] = URL(fileURLWithPath: local) }
                            }
                        }
                        let origin = RemoteFileOrigin(profile: snapshot, path: result["path"] as? String ?? path ?? local)
                        if let documents = workspace.documents { documents.open(url, origin: origin, companions: companions, reload: reloadExisting) }
                        else { workspace.open(url, externalXYZFiles: companions) }
                        explorerVisible = true; presented = false
                    }
                    status = "Opened cached copy from \(snapshot.host). Refresh remote file to retrieve updates."
                case "edit":
                    guard let encoded = result["data"] as? String, let data = Data(base64Encoded: encoded), data.count <= 2_000_000, let text = String(data: data, encoding: .utf8) else { throw RemoteError.message("Choose a UTF-8 text file smaller than 2 MB.") }
                    editingHost = snapshot.host; editor = text; editorHash = result["sha256"] as? String ?? ""; editingPath = result["path"] as? String ?? ""
                    status = "Editing \(editingPath). Save explicitly writes this remote file."
                case "write": editorHash = result["sha256"] as? String ?? ""; status = "Remote file saved. Check workflow before submitting."
                case "upload":
                    profile.directory = result["path"] as? String ?? snapshot.directory; profile.config = result["config"] as? String ?? ""; saveProfile()
                    status = "Uploaded \(result["count"] ?? 0) input files to a new workflow folder. Edit input.yaml and headers for cluster paths and dispatch: slurm, then Check."
                    workflowRemoteSelected = true; RemoteWorkflowRuntime.shared.open(config: profile.config)
                case "check": status = "Remote workflow validates; SLURM commands found. Python: \(result["python"] ?? "")"
                case "run", "resume": status = "Remote controller launched (PID \(result["pid"] ?? "?")). Click Refresh status for SLURM progress. Closing ChemViewer leaves it running."; log = "Log: \(result["log"] ?? "")"
                case "status":
                    status = (result["running"] as? Bool ?? false) ? "Remote controller is running." : "Remote controller is idle. Inspect step results and the log for completion or errors."
                    log = (result["log_tail"] as? [String] ?? []).joined(separator: "\n")
                    runSummary = Self.summary(result)
                default: break
                }
            } catch { if token == serial { status = error.localizedDescription } }
        }
    }
    static func summary(_ result: [String: Any]) -> String {
        // Actual ChemRefine rows retain their column names and units; never infer energies.
        var lines = ["Step\tEngine\tSurvivors\tFailures\tCached"]
        for step in result["steps"] as? [[String: Any]] ?? [] {
            lines.append("\(step["step"] ?? "")\t\(step["engine"] ?? "")\t\(step["reported_survivors"] ?? 0)\t\(step["failures"] ?? 0)\t\(step["cached"] ?? false)")
        }
        lines.append("\nStep\tName\tConformer\tEnergy (Hartree)\tEnergy type")
        for step in result["results"] as? [[String: Any]] ?? [] {
            let rows = (step["results"] as? [String: Any])?["rows"] as? [[String: Any]] ?? []
            if rows.isEmpty { lines.append("\(step["step"] ?? "")\t\(step["name"] ?? "")\t—\t—\tNo results yet") }
            for row in rows { lines.append("\(step["step"] ?? "")\t\(step["name"] ?? "")\t\(row["Conformer"] ?? row["ID"] ?? "")\t\(row["Energy (Hartree)"] ?? "—")\t\(row["Energy type"] ?? "")") }
        }
        return lines.joined(separator: "\n")
    }
    func upload() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.message = "Choose a dedicated workflow input folder containing input.yaml, structures and templates. Sends input file types only; excludes hidden files, outputs and scratch. Cluster paths and dispatch must be checked before Run."
        if panel.runModal() == .OK, let folder = panel.url { perform("upload", folder: folder.path) }
    }
    func refreshOpened(_ workspace: WorkspaceStore) {
        guard let path = lastOpened, lastOpenedHost == profile.host else { return }
        perform("read", path: path, workspace: workspace, reloadExisting: true)
    }
    func request(_ payload: [String: Any], profile: RemoteProfile, edit: Bool = false, folder: String? = nil) async throws -> [String: Any] {
        if payload["action"] as? String == "authenticate" {
            disconnect()
            return try await localRequest(payload, profile: profile)
        }
        let keyData = try JSONSerialization.data(withJSONObject: [profile.host, profile.python, profile.setup])
        let key = SHA256.hash(data: keyData).map { String(format: "%02x", $0) }.joined()
        if key != sessionKey { disconnect(); sessionKey = key }
        let action = payload["action"] as? String ?? ""
        let cacheKey = payload["path"] as? String ?? "~"
        if action == "list", payload["refresh"] as? Bool != true, let cached = cachedFolders[cacheKey], Date().timeIntervalSince(cached.0) < 120 {
            var result = cached.1; result["_cached"] = true; return result
        }
        guard !channelBusy else { throw RemoteError.message("A remote request is already in progress.") }
        channelBusy = true; defer { channelBusy = false }
        var actual = payload
        if edit { actual["action"] = "read" }
        if action == "upload" {
            let prepared = try await localRequest(["action":"prepare-upload"], profile: profile, folder: folder)
            actual["files"] = prepared["files"]
        }
        if session == nil {
            connectionStatus = "Opening persistent SSH channel…"
            do {
                let prepared = try await localRequest(["action":"connection-command"], profile: profile)
                guard let arguments = prepared["arguments"] as? [String] else { throw RemoteError.message("Missing SSH command.") }
                session = try makeSession(arguments)
            } catch { disconnect(); throw error }
        }
        guard let current = session else { throw RemoteError.message("No SSH channel.") }
        let response: [String: Any]
        do { response = try await current.exchange(actual) }
        catch { if session === current { disconnect() }; throw error }
        guard session === current else { throw RemoteError.message("SSH request cancelled.") }
        if current.requests == 1 { workflowRemoteSelected = true }
        if let transport = response["transport"] as? [String: Any] {
            connectionStatus = "Connected · persistent SSH channel · request \(transport["requests"] ?? "") · \(transport["milliseconds"] ?? "") ms"
        }
        guard response["ok"] as? Bool == true else { throw RemoteError.message(response["error"] as? String ?? "Remote request failed.") }
        var result = response["result"] as? [String: Any] ?? [:]
        result["_transport"] = response["transport"]; result["_server_pid"] = response["server_pid"]
        if actual["action"] as? String == "read", !edit {
            guard let encoded = result.removeValue(forKey: "data") as? String, let bytes = Data(base64Encoded: encoded), let path = result["path"] as? String else { throw RemoteError.message("Invalid remote file data.") }
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard digest == result["sha256"] as? String else { throw RemoteError.message("Remote checksum mismatch.") }
            let fileKey = SHA256.hash(data: Data((profile.host + "\0" + path).utf8)).map { String(format: "%02x", $0) }.joined()
            let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/org.cleanroom.ChemViewer/remote/" + fileKey)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let target = cache.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
            try bytes.write(to: target, options: .atomic); result["local"] = target.path
        }
        if action == "list" {
            if cachedFolders.count >= 100 { cachedFolders.removeAll() }
            cachedFolders[cacheKey] = (Date(), result)
            if let canonical = result["path"] as? String { cachedFolders[canonical] = (Date(), result) }
        } else if action == "write" || action == "upload" || action == "create-workflow" { cachedFolders.removeAll() }
        return result
    }
    func localRequest(_ payload: [String: Any], profile: RemoteProfile, edit: Bool = false, folder: String? = nil) async throws -> [String: Any] {

        guard let script = Bundle.module.url(forResource: "remote_bridge", withExtension: "py") else { throw RemoteError.message("Missing SSH helper.") }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("chemviewer-ssh-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: temporary) }
        let input = temporary.appendingPathComponent("request.json"), output = temporary.appendingPathComponent("response.json")
        var actual = payload; if edit { actual["action"] = "read" }
        var message: [String: Any] = ["profile": try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)), "request": actual, "edit": edit]
        if let folder { message["folder"] = folder }
        try JSONSerialization.data(withJSONObject: message).write(to: input)
        let job = Process(); job.executableURL = FileManager.default.isExecutableFile(atPath: ChemistryRuntime.python.path) ? ChemistryRuntime.python : URL(fileURLWithPath: "/usr/bin/python3"); job.arguments = [script.path, input.path, output.path]
        let err = temporary.appendingPathComponent("stderr"); FileManager.default.createFile(atPath: err.path, contents: nil)
        let handle = try FileHandle(forWritingTo: err); defer { try? handle.close() }; job.standardError = handle
        job.standardOutput = FileHandle.nullDevice
        process = job
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            job.terminationHandler = { _ in continuation.resume() }
            do { try job.run() } catch { job.terminationHandler = nil; continuation.resume(throwing: error) }
        }
        guard FileManager.default.fileExists(atPath: output.path) else { throw RemoteError.message(String(data: (try? Data(contentsOf: err)) ?? Data(), encoding: .utf8) ?? "SSH helper failed.") }
        let response = try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any] ?? [:]
        guard response["ok"] as? Bool == true else { throw RemoteError.message(response["error"] as? String ?? "Remote request failed.") }
        return response["result"] as? [String: Any] ?? [:]
    }
}

enum RemoteError: LocalizedError { case message(String); var errorDescription: String? { if case .message(let text) = self { return text }; return nil } }

struct RemoteConnectionView: View {
    @ObservedObject private var remote = RemoteConnection.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SSH connection").font(.title2)
                Spacer()
                Menu("Connections") {
                    ForEach(remote.profiles) { profile in Button(profile.name) { remote.selectProfile(profile.id) } }
                    Divider()
                    Button("New connection") { remote.clearExplorer(); remote.profile = RemoteProfile() }
                }.disabled(remote.busy)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow { Text("Name"); TextField("Connection name", text: $remote.profile.name) }
                GridRow { Text("SSH host"); TextField("Alias from ~/.ssh/config or user@host", text: $remote.profile.host) }
                GridRow { Text("Starting folder"); TextField("~", text: $remote.profile.directory) }
                GridRow { Text("ChemRefine Python"); TextField("Python executable or environment folder", text: $remote.profile.python) }
            }.disabled(remote.busy)
            DisclosureGroup("Environment commands") {
                TextEditor(text: $remote.profile.setup).font(.system(.caption, design: .monospaced)).frame(height: 70)
                Text("Executed remotely before Python starts. Compute-node activation belongs in the workflow’s SLURM headers.").font(.caption).foregroundStyle(.secondary)
            }.disabled(remote.busy)
            HStack {
                Button("Save") { remote.saveProfile() }
                Button("Authenticate in Terminal") { remote.perform("authenticate") }
                Button("Connect / Browse") { remote.perform("list") }
                Button("Check environment") { remote.perform("info") }
            }.disabled(remote.busy)
            Text(remote.status).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if !remote.editingPath.isEmpty {
                Divider()
                Text(remote.editingPath).font(.caption).textSelection(.enabled)
                TextEditor(text: $remote.editor).font(.system(.caption, design: .monospaced)).frame(minHeight: 130)
                Button("Save remote text file") { remote.perform("write", path: remote.editingPath) }.disabled(remote.busy)
            }
            Spacer(minLength: 0)
            Divider()
            Text("Browse files in the left explorer. Build and submit calculations in the ChemRefine tab.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(remote.connectionStatus).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if remote.busy { ProgressView().controlSize(.small); Button("Cancel request") { remote.cancel() } }
                Button("Disconnect") { RemoteWorkflowRuntime.shared.stop(); remote.disconnect() }.disabled(remote.busy)
            }
        }.padding(20).frame(minWidth: 680, idealWidth: 760, minHeight: 430)
    }
}
