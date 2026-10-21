import AppKit
import ChemCraftCore
import CryptoKit
import WebKit
import SwiftUI

/// Opt-in live test: exclusively creates synthetic inputs, rejects dispatch:local, submits no jobs.
@MainActor
enum RemoteWorkflowSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        let remote = RemoteConnection.shared, runtime = RemoteWorkflowRuntime.shared
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: "ChemViewerSSHProfiles")
        let shown = defaults.object(forKey: "ChemViewerRemoteExplorerVisible")
        func restore() {
            runtime.stop(); remote.disconnect()
            if let saved { defaults.set(saved, forKey: "ChemViewerSSHProfiles") } else { defaults.removeObject(forKey: "ChemViewerSSHProfiles") }
            if let shown { defaults.set(shown, forKey: "ChemViewerRemoteExplorerVisible") } else { defaults.removeObject(forKey: "ChemViewerRemoteExplorerVisible") }
        }
        func require(_ value: Bool, _ message: String) throws { if !value { throw ParseError.malformed(message) } }
        func find(_ view: NSView) -> WKWebView? { if let web = view as? WKWebView { return web }; return view.subviews.compactMap(find).first }
        do {
            for _ in 0..<600 { if !workspace.isLoading && !remote.busy { break }; try await Task.sleep(nanoseconds: 50_000_000) }
            guard let frame = workspace.currentFrame else { throw ParseError.malformed("Launch with independent water.xyz fixture") }
            runtime.stop()
            remote.workflowRemoteSelected = true
            // Create before displaying the tab so an automatic blank editor cannot race it.
            runtime.create(workspace: workspace, parent: "~")
            workspace.activeTab = "ChemRefine"
            for _ in 0..<400 { if !runtime.busy { break }; try await Task.sleep(nanoseconds: 150_000_000) }
            try require(runtime.guiURL != nil, "Remote editor failed: \(runtime.status)")
            guard let web = NSApp.windows.compactMap(\.contentView).compactMap(find).first else { throw ParseError.malformed("Remote editor not mounted in ChemRefine tab") }
            var ready = false
            for _ in 0..<200 {
                ready = (try? await web.evaluateJavaScript("!!(window.Alpine && Alpine.$data(document.body).savedPath)")) as? Bool == true
                if ready { break }; try await Task.sleep(nanoseconds: 100_000_000)
            }
            try require(ready, "Remote editor did not load configuration")
            let connectedURL = runtime.guiURL
            _ = try await web.evaluateJavaScript("Alpine.$data(document.body).cfg.steps[0].name='unsaved_draft_survives_idle'; true")
            for _ in 0..<20 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try require(runtime.guiURL == connectedURL, "Editor disconnected after successful forwarding setup: \(runtime.status)")
            }
            let draft = try await web.evaluateJavaScript("Alpine.$data(document.body).cfg.steps[0].name") as? String
            try require(draft == "unsaved_draft_survives_idle", "Connection monitoring reloaded an unsaved draft")
            let health = try await web.callAsyncJavaScript("const r=await fetch('/'); return r.status;", arguments:[:],in:nil,contentWorld:.page) as? Int
            try require(health == 200, "Forward stopped serving after setup process exited")
            let config = try await web.evaluateJavaScript("JSON.stringify(Alpine.$data(document.body).cfg)") as! String
            let cfg = try JSONSerialization.jsonObject(with: Data(config.utf8)) as! [String:Any]
            try require(cfg["dispatch"] as? String == "slurm" && cfg["input"] as? String == "seed.xyz", "Remote defaults did not use relative paths and SLURM")
            try require((cfg["executables"] as? [String:Any])?["orca"] as? String == "orca", "Mac executable leaked into remote workflow")
            let path = try await runtime.saveEditor()
            try require(!path.hasPrefix("/Users/"), "Remote editor saved to Mac path")
            let evidence = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/chemviewer-remote-evidence")
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
            let digest = SHA256.hash(data: Data(XYZWriter.string(frame:frame).utf8)).map { String(format:"%02x",$0) }.joined()
            try JSONSerialization.data(withJSONObject:["path":URL(fileURLWithPath:path).deletingLastPathComponent().path,"seed_sha256":digest]).write(to:evidence.appendingPathComponent("live-workflow-test.json"))
            let browserResult = try await web.callAsyncJavaScript("const b=Alpine.$data(document.body); const r=await b.api('GET','/api/browse?path='+encodeURIComponent(parent)); return JSON.stringify(r);", arguments:["parent":URL(fileURLWithPath:path).deletingLastPathComponent().path],in:nil,contentWorld:.page) as? String ?? ""
            try require(browserResult.contains("seed.xyz") && browserResult.contains("templates"), "Remote editor file chooser did not browse cluster inputs")
            _ = try await web.evaluateJavaScript("var b=Alpine.$data(document.body); b.cfg.dispatch='local'; b.tmpl={open:true,step:1,text:'! HF STO-3G\\n'}; true")
            _ = try await runtime.execute("save")
            let template = try await remote.request(["action":"read","path":URL(fileURLWithPath:path).deletingLastPathComponent().appendingPathComponent("templates/cleanup.inp").path],profile:remote.profile,edit:true)
            try require((template["data"] as? String).flatMap { Data(base64Encoded:$0) }.flatMap { String(data:$0,encoding:.utf8) } == "! HF STO-3G\n", "Remote template draft was not saved")
            do { _ = try await runtime.execute("run"); throw ParseError.malformed("Remote execution accepted dispatch:local") }
            catch let error as RemoteError { try require(error.localizedDescription.contains("dispatch: slurm"), "Wrong preflight refusal: \(error)") }
            let intercepted = try await web.callAsyncJavaScript("const r=await fetch('/api/run',{method:'POST',body:JSON.stringify({action:'resume'})}); return JSON.stringify({status:r.status,body:await r.json()});",arguments:[:],in:nil,contentWorld:.page) as? String ?? ""
            try require(intercepted.contains("400") && intercepted.contains("dispatch: slurm"), "Embedded Run/Resume bypassed remote native preflight")
            _ = try await web.evaluateJavaScript("Alpine.$data(document.body).cfg.dispatch='slurm'; true")
            _ = try await runtime.execute("save")
            try await Task.sleep(nanoseconds: 300_000_000)
            if let window = NSApp.windows.first(where:{$0.isVisible && $0.sheetParent == nil}),let image = CGWindowListCreateImage(.null,.optionIncludingWindow,CGWindowID(window.windowNumber),[.boundsIgnoreFraming,.bestResolution]),let png = NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) { try png.write(to:evidence.appendingPathComponent("remote-chemrefine-tab.png")) }
            remote.profile.directory = URL(fileURLWithPath:path).deletingLastPathComponent().path
            let picker = NSWindow(contentRect: NSRect(x:100,y:100,width:700,height:500), styleMask:[.titled,.closable], backing:.buffered, defer:false)
            picker.title = "ChemViewer — remote workflow picker"
            picker.contentView = NSHostingView(rootView: RemoteWorkflowPicker(kind:.workflow) { _ in })
            picker.makeKeyAndOrderFront(nil)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try require(!NSApp.windows.contains(where: { $0.isVisible && $0 is NSOpenPanel }), "Remote operation opened a local file chooser")
            if let image = CGWindowListCreateImage(.null,.optionIncludingWindow,CGWindowID(picker.windowNumber),[.boundsIgnoreFraming,.bestResolution]),let png = NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) { try png.write(to:evidence.appendingPathComponent("remote-workflow-picker.png")) }
            picker.orderOut(nil); picker.contentView = nil
            let oldURL = runtime.guiURL!
            runtime.stop()
            var closed = false
            for _ in 0..<30 {
                var request = URLRequest(url: oldURL); request.timeoutInterval = 0.5
                if (try? await URLSession.shared.data(for:request)) == nil { closed = true; break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try require(closed, "Closing editor left its loopback forward listening on the shared master")
            print("REMOTE_WORKFLOW_PASS: 20-second idle/draft/HTTP survival beyond setup-process exit and exact forwarding cleanup; live SSH editor embedded in ChemRefine tab, remote filesystem browse, exclusive workflow/structure creation, dispatch:slurm and relative-path defaults, saved template draft, native plus web Run/Resume preflight rejects local dispatch; no jobs submitted. Fixture metadata saved for guarded cleanup.")
            restore(); fflush(stdout); exit(0)
        } catch { restore(); print("REMOTE_WORKFLOW_FAIL: \(error)"); fflush(stdout); exit(1) }
    }
}
