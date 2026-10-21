import AppKit
import ChemCraftCore
import SwiftUI
import Vision

/// Real SwiftUI sidebar + native persistent RPC, with independent local folder fixtures.
@MainActor
enum RemoteExplorerSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey: "ChemViewerSSHProfiles")
        let shown = defaults.object(forKey: "ChemViewerRemoteExplorerVisible")
        let order = defaults.object(forKey: "ChemViewerRemoteExplorerOrder")
        func restore() {
            if let saved { defaults.set(saved, forKey: "ChemViewerSSHProfiles") } else { defaults.removeObject(forKey: "ChemViewerSSHProfiles") }
            if let shown { defaults.set(shown, forKey: "ChemViewerRemoteExplorerVisible") } else { defaults.removeObject(forKey: "ChemViewerRemoteExplorerVisible") }
            if let order { defaults.set(order, forKey: "ChemViewerRemoteExplorerOrder") } else { defaults.removeObject(forKey: "ChemViewerRemoteExplorerOrder") }
        }
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw ParseError.malformed(message) } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("chemviewer-explorer-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory); restore() }
        do {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("calculations"), withIntermediateDirectories: true)
            for name in ["LICENSE", "a.xyz", "B.OUT", "z.inp", "b2.out", "b10.out"] { try "fixture".write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8) }
            try "ordinary file".write(to: directory.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
            try "2\nH2\nH 0 0 0\nH 0 0 0.74\n".write(to: directory.appendingPathComponent("molecule.xyz"), atomically: true, encoding: .utf8)
            let python = ChemistryRuntime.python
            let agent = Bundle.module.url(forResource: "remote_agent", withExtension: "py")!
            var startups = 0
            let remote = RemoteConnection(makeSession: { _ in
                startups += 1
                return try RemoteSSHSession(arguments: [python.path, agent.path, "--chemviewer-serve"], executable: python)
            })
            defer { remote.disconnect() }
            remote.profile = RemoteProfile(host: "synthetic-explorer", directory: directory.path)
            // Reproduce a sidebar first mounted while authentication/another request is busy.
            remote.busy = true
            let window = NSWindow(contentRect: NSRect(x: 100,y: 100,width: 440,height: 560), styleMask: [.titled,.closable,.resizable], backing: .buffered, defer: false)
            window.title = "ChemViewer — explorer regression"
            window.contentView = NSHostingView(rootView: RemoteExplorerView(remote: remote).environmentObject(workspace))
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil); window.contentView = nil }
            try await Task.sleep(nanoseconds: 600_000_000)
            try require(remote.explorerRoot.isEmpty, "Sidebar ignored busy connection")
            remote.busy = false
            func loaded(_ path: String) async throws {
                for _ in 0..<200 {
                    if !remote.busy && remote.explorerNodes[path] != nil { return }
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                throw ParseError.malformed("Sidebar failed to populate automatically: \(remote.status)")
            }
            try await loaded(directory.path)
            try require(remote.explorerNodes[directory.path]?.count == 9, "Sidebar dropped directories or ordinary files")
            remote.toggleExplorerFolder(directory.path + "/calculations", expanded: true)
            try await loaded(directory.path + "/calculations")
            try require(remote.explorerNodes[directory.path + "/calculations"]?.isEmpty == true, "Empty child folder not represented")
            remote.explorerNodes = [:] // Root exists but missing contents: remount must reload it.
            window.contentView = nil
            window.contentView = NSHostingView(rootView: RemoteExplorerView(remote: remote).environmentObject(workspace))
            try await loaded(directory.path)
            try require(startups == 1, "Sidebar navigation restarted persistent helper")
            remote.explorerOrder = .fileExtension
            let expected = ["calculations", "LICENSE", "z.inp", "B.OUT", "b2.out", "b10.out", "README.txt", "a.xyz", "molecule.xyz"]
            try require(remote.sortedExplorerEntries(directory.path).map(\.name) == expected, "Extension ordering did not group mixed-case extensions, keep folders first, and naturally sort numeric names")
            remote.explorerOrder = .name
            try require(remote.sortedExplorerEntries(directory.path).dropFirst().first?.name == "a.xyz", "Name sort did not restore name ordering")
            remote.explorerOrder = .fileExtension
            try require(RemoteConnection().explorerOrder == .fileExtension, "Sort choice did not persist")
            // Locate the actual rendered label in this window, then deliver native double-click events.
            try await Task.sleep(nanoseconds: 300_000_000)
            guard let screenshot = CGWindowListCreateImage(.null,.optionIncludingWindow,CGWindowID(window.windowNumber),[.boundsIgnoreFraming,.bestResolution]) else { throw ParseError.malformed("Cannot capture explorer window for native click test") }
            let recognize = VNRecognizeTextRequest(); recognize.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage:screenshot).perform([recognize])
            guard let label = recognize.results?.first(where: { $0.topCandidates(1).first?.string.lowercased().contains("calculations") == true }) else { throw ParseError.malformed("Rendered folder label not found in explorer window") }
            let point = NSPoint(x: label.boundingBox.midX * window.frame.width, y: label.boundingBox.midY * window.frame.height)
            for count in 1...2 {
                for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = NSEvent.mouseEvent(with: kind, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: count, clickCount: count, pressure: 1)!
                    window.sendEvent(event)
                }
                try await Task.sleep(nanoseconds: 80_000_000)
            }
            for _ in 0..<100 { if remote.explorerRoot == directory.path + "/calculations" && !remote.busy { break }; try await Task.sleep(nanoseconds: 50_000_000) }
            try require(remote.explorerRoot == directory.path + "/calculations", "Native double-click did not enter directory")
            remote.enterExplorerFolder(directory.path); try await loaded(directory.path)
            for _ in 0..<100 { if !remote.busy { break }; try await Task.sleep(nanoseconds: 50_000_000) }
            try require(remote.explorerRoot == directory.path && startups == 1, "Parent navigation changed connection or failed")
            let root = remote.explorerRoot
            remote.profile.host = "different-synthetic-host"
            try require(remote.explorerRoot.isEmpty && remote.explorerNodes.isEmpty, "Connection settings retained another host's folder tree")
            try await Task.sleep(nanoseconds: 100_000_000)
            remote.profile.host = "synthetic-explorer"
            remote.profile.directory = root
            try await loaded(directory.path)
            try await Task.sleep(nanoseconds: 300_000_000)
            let evidence = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/chemviewer-remote-evidence")
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
            if let image = CGWindowListCreateImage(.null,.optionIncludingWindow,CGWindowID(window.windowNumber),[.boundsIgnoreFraming,.bestResolution]), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try png.write(to: evidence.appendingPathComponent("explorer-loading-regression.png"))
            }
            print("REMOTE_EXPLORER_PASS: native sidebar auto-loads after busy authentication, shows mixed entries, persists natural name/extension sorting, native double-click enters folder with cached return, expands empty child, reloads missing root nodes, reuses helper, and reloads after connection identity changes; no SSH/compute jobs.")
            restore(); remote.disconnect(); fflush(stdout); exit(0)
        } catch { restore(); print("REMOTE_EXPLORER_FAIL: \(error)"); fflush(stdout); exit(1) }
    }
}
