import AppKit
import ChemCraftCore
import Foundation

/// Opt-in, read-only timings using the saved authenticated connection.
@MainActor
enum RemoteNavigationSmokeTest {
    static var started = false
    static func run() async {
        guard !started else { return }; started = true
        let remote = RemoteConnection()
        defer { remote.disconnect() }
        do {
            let profile = remote.profile
            guard !profile.host.isEmpty else { throw ParseError.malformed("No saved remote profile") }
            var start = Date()
            let first = try await remote.request(["action":"list","path":profile.directory,"refresh":true], profile: profile)
            let firstMS = Int(Date().timeIntervalSince(start) * 1000)
            let canonical = first["path"] as! String
            start = Date()
            let warm = try await remote.request(["action":"list","path":canonical,"refresh":true], profile: profile)
            let warmMS = Int(Date().timeIntervalSince(start) * 1000)
            start = Date()
            let cached = try await remote.request(["action":"list","path":canonical], profile: profile)
            let cachedMS = Int(Date().timeIntervalSince(start) * 1000)
            guard let pid = first["_server_pid"] as? Int, warm["_server_pid"] as? Int == pid, cached["_cached"] as? Bool == true, (warm["_transport"] as? [String:Any])?["requests"] as? Int == 2 else { throw ParseError.malformed("Navigation did not preserve remote process/cache") }
            let sidebar = RemoteConnection.shared
            sidebar.explorerVisible = true
            await sidebar.ensureExplorerLoaded()
            for _ in 0..<600 {
                if !sidebar.busy && sidebar.explorerNodes[sidebar.explorerRoot] != nil { break }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            guard let visible = sidebar.explorerNodes[sidebar.explorerRoot], !visible.isEmpty else { throw ParseError.malformed("Live sidebar remained empty: \(sidebar.status)") }
            try await Task.sleep(nanoseconds: 500_000_000)
            let evidence = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/chemviewer-remote-evidence")
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent == nil }), let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try png.write(to: evidence.appendingPathComponent("live-explorer-0110.png"))
            }
            print("REMOTE_SIDEBAR_LIVE_PASS entries=\(visible.count) directories=\(visible.filter { $0.directory }.count) no_jobs_submitted=true")
            sidebar.disconnect()
            print("REMOTE_NAVIGATION_PASS first_ms=\(firstMS) warm_uncached_ms=\(warmMS) cached_ms=\(cachedMS) same_remote_pid=true network_requests=2 no_jobs_submitted=true")
            fflush(stdout); exit(0)
        } catch { print("REMOTE_NAVIGATION_FAIL: \(error)"); fflush(stdout); exit(1) }
    }
}
