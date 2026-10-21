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
            print("REMOTE_NAVIGATION_PASS first_ms=\(firstMS) warm_uncached_ms=\(warmMS) cached_ms=\(cachedMS) same_remote_pid=true network_requests=2 no_jobs_submitted=true")
            fflush(stdout); exit(0)
        } catch { print("REMOTE_NAVIGATION_FAIL: \(error)"); fflush(stdout); exit(1) }
    }
}
