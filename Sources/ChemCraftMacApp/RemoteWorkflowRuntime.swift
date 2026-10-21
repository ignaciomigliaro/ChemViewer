import AppKit
import ChemCraftCore
import SwiftUI
import WebKit

/// A remote ChemRefine editor over private loopback SSH forwarding. No Mac paths are injected.
@MainActor
final class RemoteWorkflowRuntime: ObservableObject {
    static let shared = RemoteWorkflowRuntime()
    @Published var requestedPicker: RemoteWorkflowPicker.Kind?
    @Published var guiURL: URL?
    @Published var busy = false
    @Published var status = "Open a cluster workflow, or create one from the current structure."
    @Published var results = ""
    private var server: Process?
    private var tunnel: Process?
    private var cancelForwardArguments: [String]?
    private var input: Pipe?
    private var browser: WKWebView?
    private var delegate: RemoteWorkflowDelegate?
    private var generation = 0
    private var identity = ""
    private var scratch: URL?
    private var observer: NSObjectProtocol?
    init() {
        observer = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { RemoteWorkflowRuntime.shared.stop() }
        }
    }
    func stop() {
        generation += 1
        try? input?.fileHandleForWriting.close(); input = nil
        // EOF tells our remote wrapper to terminate its own GUI child; no user jobs are killed.
        if let tunnel, tunnel.isRunning { tunnel.terminate() }; tunnel = nil
        if let args = cancelForwardArguments {
            let cancel = Process(); cancel.executableURL = URL(fileURLWithPath: args[0]); cancel.arguments = Array(args.dropFirst())
            cancel.standardInput = FileHandle.nullDevice; cancel.standardOutput = FileHandle.nullDevice; cancel.standardError = FileHandle.nullDevice
            try? cancel.run() // Cancel only this loopback binding, never the shared SSH master.
        }
        cancelForwardArguments = nil
        if let job = server {
            Task { try? await Task.sleep(nanoseconds: 7_000_000_000); if job.isRunning { job.terminate() } }
        }
        server = nil; browser?.stopLoading(); browser = nil; delegate = nil; guiURL = nil; busy = false; results = ""
        if let scratch { try? FileManager.default.removeItem(at: scratch) }; scratch = nil
    }
    func open(config: String = "") {
        let remote = RemoteConnection.shared
        guard !busy, !remote.profile.host.isEmpty else { return }
        stop(); generation += 1; let token = generation
        let profile = remote.profile; identity = remote.explorerIdentity
        busy = true; status = "Starting ChemRefine on \(profile.host)…"
        Task {
            defer { if token == generation { busy = false } }
            do {
                let prepared = try await remote.localRequest(["action":"gui-command", "path":config], profile: profile)
                guard token == generation, let args = prepared["arguments"] as? [String] else { return }
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("chemviewer-remote-gui-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]); scratch = folder
                let log = folder.appendingPathComponent("gui.log")
                FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
                let output = try FileHandle(forWritingTo: log); defer { try? output.close() }
                let job = Process(); job.executableURL = URL(fileURLWithPath: args[0]); job.arguments = Array(args.dropFirst())
                let stdin = Pipe(); job.standardInput = stdin; input = stdin
                job.standardOutput = output; job.standardError = output; try job.run(); server = job
                var remoteURL: URL?
                for _ in 0..<200 {
                    guard token == generation else { return }
                    let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
                    if let range = text.range(of: #"http://127\.0\.0\.1:\d+/\?token=[A-Za-z0-9_-]+"#, options: .regularExpression) { remoteURL = URL(string: String(text[range])); break }
                    if !job.isRunning { throw ParseError.malformed("Remote editor could not start. Verify ChemRefine[gui] in the selected SSH Python environment and authenticate in SSH settings.") }
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
                guard let remoteURL, let port = remoteURL.port else { throw ParseError.malformed("Remote editor startup timed out. Check SSH settings and the remote GUI installation.") }
                let forward = try await remote.localRequest(["action":"tunnel-command", "port":port], profile: profile)
                guard token == generation, let forwardArgs = forward["arguments"] as? [String], let localPort = forward["port"] as? Int else { return }
                guard let cancellation = forward["cancel_arguments"] as? [String] else { throw ParseError.malformed("Missing SSH forwarding cleanup command.") }
                cancelForwardArguments = cancellation
                let link = Process(); link.executableURL = URL(fileURLWithPath: forwardArgs[0]); link.arguments = Array(forwardArgs.dropFirst())
                link.standardInput = FileHandle.nullDevice; link.standardOutput = output; link.standardError = output; try link.run(); tunnel = link
                var confirmed = false
                for _ in 0..<100 {
                    guard token == generation else { return }
                    if !link.isRunning {
                        guard link.terminationStatus == 0 else { throw ParseError.malformed("SSH could not create the editor forward. Reconnect in SSH settings and retry.") }
                        confirmed = true; break
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                guard confirmed else { throw ParseError.malformed("SSH forwarding setup timed out.") }
                var components = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false)!; components.port = localPort
                let local = components.url!
                var ready = false
                for _ in 0..<60 {
                    guard token == generation else { return }
                    var request = URLRequest(url: local); request.timeoutInterval = 1
                    if let (_, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200 { ready = true; break }
                    try await Task.sleep(nanoseconds: 150_000_000)
                }
                guard ready, token == generation else { throw ParseError.malformed("The SSH tunnel did not become ready.") }
                guiURL = local; remote.profile.config = config; remote.saveProfile()
                status = "Connected to \(profile.host). Files, templates and environment paths belong to this host."
                Task {
                    while token == generation {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        guard token == generation else { return }
                        if !job.isRunning { stop(); status = "Remote editor disconnected. Reopen it to reconnect; submitted jobs continue independently."; return }
                    }
                }
            } catch { if token == generation { stop(); status = error.localizedDescription } }
        }
    }
    func webView(_ url: URL) -> WKWebView {
        if let browser { return browser }
        let configuration = WKWebViewConfiguration()
        let handler = RemoteWorkflowDelegate(runtime: self, allowedURL: url)
        configuration.userContentController.addScriptMessageHandler(handler, contentWorld: .page, name: "chemViewerRemoteWorkflow")
        let script = """
        (() => {
          const original = window.fetch.bind(window);
          window.fetch = async (resource, options = {}) => {
            const u = new URL(typeof resource === 'string' ? resource : resource.url, location.href);
            if (u.origin === location.origin && u.pathname === '/api/run' && String(options.method).toUpperCase() === 'POST') {
              try {
                const payload = JSON.parse(options.body || '{}');
                const result = await window.webkit.messageHandlers.chemViewerRemoteWorkflow.postMessage(payload);
                return new Response(JSON.stringify(result), {status:200});
              } catch(e) { return new Response(JSON.stringify({error:String(e.message || e)}), {status:400}); }
            }
            return original(resource, options);
          };
        })();
        """
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: configuration)
        delegate = handler; view.uiDelegate = handler; view.load(URLRequest(url: url)); browser = view
        return view
    }
    func saveEditor() async throws -> String {
        guard let browser, identity == RemoteConnection.shared.explorerIdentity else { throw ParseError.malformed("Open the workflow on the current SSH connection first.") }
        let script = """
        const b = window.Alpine && Alpine.$data(document.body);
        if (!b?.savedPath) throw new Error('Save the remote workflow as input.yaml first.');
        if (!b.rawEdit) {
          clearTimeout(b._timer);
          const emitted = await b.api('POST', '/api/yaml', {config:b.cfg});
          if (!emitted) throw new Error(b.flash || 'Could not read workflow.');
          b.yamlText = emitted.yaml_text;
        }
        const saved = await b.api('POST', '/api/save', {path:b.savedPath, yaml_text:b.yamlText});
        if (!saved) throw new Error(b.flash || 'Could not save remote workflow.');
        if (b.tmpl?.open) {
          const t = await b.api('POST', '/api/template', {config_path:saved.path, step:b.tmpl.step, text:b.tmpl.text});
          if (!t) throw new Error(b.flash || 'Could not save template.');
          b.tmpl.open = false;
        }
        b.savedText = b.yamlText; return saved.path;
        """
        guard let path = try await browser.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page) as? String else { throw ParseError.malformed("Remote editor returned no workflow path.") }
        RemoteConnection.shared.profile.config = path; RemoteConnection.shared.saveProfile(); return path
    }
    func execute(_ action: String, target: Any? = nil) async throws -> [String:Any] {
        let remote = RemoteConnection.shared
        guard !busy, !remote.busy else { throw ParseError.malformed("Wait for the current request to finish.") }
        guard ["save","check","status"].contains(action) || WorkflowRunner.launchActions.contains(action) else { throw ParseError.malformed("Unknown remote workflow action.") }
        let profile = remote.profile, connectionIdentity = remote.explorerIdentity
        busy = true; remote.busy = true; defer { busy = false; remote.busy = false }
        do {
            let path: String
            if action == "status" {
                guard let browser, let saved = try await browser.evaluateJavaScript("window.Alpine && Alpine.$data(document.body).savedPath") as? String else { throw ParseError.malformed("Open a remote workflow first.") }
                path = saved
            } else { path = try await saveEditor() }
            guard remote.explorerIdentity == connectionIdentity else { throw ParseError.malformed("SSH connection changed. Reopen the workflow on the selected host.") }
            if action == "save" { status = "Saved remote workflow and edited template."; return ["saved":true] }
            var payload: [String:Any] = ["action":action, "path":path]
            if let target, !(target is NSNull) { payload["target"] = target }
            let result = try await remote.request(payload, profile: profile)
            if action == "status" { results = RemoteConnection.summary(result); status = result["running"] as? Bool == true ? "Remote controller is running." : "Remote controller is idle." }
            else if action == "check" { status = "Remote workflow validates; SLURM commands and declared files found." }
            else { status = "SLURM workflow controller started (PID \(result["pid"] ?? "?")). Jobs continue after closing this editor." }
            return result
        } catch { status = error.localizedDescription; throw error }
    }
    func perform(_ action: String) { Task { do { _ = try await execute(action) } catch { status = error.localizedDescription } } }
    func create(workspace: WorkspaceStore, parent: String) {
        guard !busy, let frame = workspace.currentFrame, !frame.atoms.isEmpty, !frame.atoms.contains(where: { $0.element == "X" }) else { status = "Build a structure and remove unused dummy atoms first."; return }
        let remote = RemoteConnection.shared
        guard !remote.busy else { status = "Wait for the current remote request to finish."; return }
        let profile = remote.profile, connectionIdentity = remote.explorerIdentity
        generation += 1; let token = generation
        let yaml = """
        input: seed.xyz
        template_dir: templates
        output_dir: outputs
        scratch_dir: scratch
        charge: \(workspace.charge)
        multiplicity: \(workspace.multiplicity)
        max_cores: 4
        dispatch: slurm
        slurm_template: cpu.slurm.header
        executables:
          orca: orca
        steps:
          - step: 1
            name: cleanup
            engine: orca
            template: cleanup.inp
        """ + "\n"
        let files = ["input.yaml":yaml, "seed.xyz":XYZWriter.string(frame: frame), "templates/cleanup.inp":"! XTB2 Opt\n", "templates/cpu.slurm.header":"#!/bin/bash\n#SBATCH --job-name=chemrefine\n#SBATCH --ntasks=4\n#SBATCH --cpus-per-task=1\n# Add cluster account/partition/time and module or environment setup here.\n"]
        busy = true; remote.busy = true; status = "Creating a new workflow folder on \(profile.host)…"
        Task {
            do {
                let result = try await remote.request(["action":"create-workflow", "path":parent, "files":files.mapValues { Data($0.utf8).base64EncodedString() }], profile: profile)
                guard token == generation, connectionIdentity == remote.explorerIdentity else { remote.busy = false; return }
                guard let config = result["config"] as? String else { throw ParseError.malformed("No remote workflow was created.") }
                remote.busy = false; busy = false; open(config: config)
            } catch { remote.busy = false; if token == generation { busy = false; status = error.localizedDescription } }
        }
    }
}

@MainActor
private final class RemoteWorkflowDelegate: NSObject, WKUIDelegate, WKScriptMessageHandlerWithReply {
    weak var runtime: RemoteWorkflowRuntime?
    let allowedURL: URL
    private let dialogs = ChemRefineWebDelegate()
    init(runtime: RemoteWorkflowRuntime, allowedURL: URL) { self.runtime = runtime; self.allowedURL = allowedURL }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, let url = message.frameInfo.request.url, url.host == "127.0.0.1", url.port == allowedURL.port,
              let payload = message.body as? [String:Any], let action = payload["action"] as? String, let runtime else { replyHandler(nil,"Invalid remote editor origin."); return }
        Task { do { replyHandler(try await runtime.execute(action, target: payload["target"]), nil) } catch { replyHandler(nil,error.localizedDescription) } }
    }
    func webView(_ view: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) { dialogs.webView(view, runJavaScriptConfirmPanelWithMessage: message, initiatedByFrame: frame, completionHandler: completionHandler) }
    func webView(_ view: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) { dialogs.webView(view, runJavaScriptAlertPanelWithMessage: message, initiatedByFrame: frame, completionHandler: completionHandler) }
    func webView(_ view: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) { dialogs.webView(view, runJavaScriptTextInputPanelWithPrompt: prompt, defaultText: defaultText, initiatedByFrame: frame, completionHandler: completionHandler) }
}
