import AppKit
import ChemCraftCore
import Foundation

@MainActor
enum RemoteSessionSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw ParseError.malformed(message) } }
        do {
            let agent = Bundle.module.url(forResource: "remote_agent", withExtension: "py")!
            let python = FileManager.default.isExecutableFile(atPath: ChemistryRuntime.python.path) ? ChemistryRuntime.python : URL(fileURLWithPath: "/usr/bin/python3")
            let session = try RemoteSSHSession(arguments: [python.path, agent.path, "--chemviewer-serve"], executable: python)
            defer { session.close() }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("chemviewer-session-fixture-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("child"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let original = "2\nIndependent wire fixture\nH 0 0 0\nH 0 0 0.74\n"
            try original.write(to: directory.appendingPathComponent("seed.xyz"), atomically: true, encoding: .utf8)
            let first = try await session.exchange(["action":"list", "path":directory.path])
            let child = try await session.exchange(["action":"list", "path":directory.appendingPathComponent("child").path])
            let failure = try await session.exchange(["action":"list", "path":directory.appendingPathComponent("absent").path])
            let read = try await session.exchange(["action":"read", "path":directory.appendingPathComponent("seed.xyz").path])
            try require(first["ok"] as? Bool == true && child["ok"] as? Bool == true && failure["ok"] as? Bool == false && read["ok"] as? Bool == true, "RPC failure did not preserve session for subsequent requests")
            let pid = first["server_pid"] as? Int
            try require(pid != nil && pid == child["server_pid"] as? Int && pid == read["server_pid"] as? Int, "Folder navigation restarted the helper")
            let data = (read["result"] as? [String:Any])?["data"] as? String
            try require(data.flatMap { Data(base64Encoded: $0) } == Data(original.utf8), "Persistent wire changed XYZ contents")
            try require(session.requests == 4 && (read["transport"] as? [String:Any])?["reused"] as? Bool == true, "Persistent channel counter/reuse is wrong")
            session.close()
            var startups = 0
            let connection = RemoteConnection(makeSession: { _ in
                startups += 1
                return try RemoteSSHSession(arguments: [python.path, agent.path, "--chemviewer-serve"], executable: python)
            })
            defer { connection.disconnect() }
            let profile = RemoteProfile(host: "synthetic-cache-test")
            let root = try await connection.request(["action":"list", "path":directory.path], profile: profile)
            let nested = try await connection.request(["action":"list", "path":directory.appendingPathComponent("child").path], profile: profile)
            let cached = try await connection.request(["action":"list", "path":directory.path], profile: profile)
            try require(cached["_cached"] as? Bool == true && startups == 1, "Parent navigation reopened a connection")
            try require(root["_server_pid"] as? Int == nested["_server_pid"] as? Int, "Distinct folders restarted the server")
            try "refresh fixture".write(to: directory.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
            let refreshed = try await connection.request(["action":"list", "path":directory.path, "refresh":true], profile: profile)
            try require((refreshed["entries"] as? [[String:Any]] ?? []).contains(where: { $0["name"] as? String == "new.txt" }), "Refresh did not retrieve directory changes")
            try require((refreshed["_transport"] as? [String:Any])?["requests"] as? Int == 3 && startups == 1, "Cache/refresh did not reuse one channel")
            let file = try await connection.request(["action":"read", "path":directory.appendingPathComponent("seed.xyz").path], profile: profile)
            guard let local = file["local"] as? String else { throw ParseError.malformed("No cached XYZ path") }
            let actual = try Data(contentsOf: URL(fileURLWithPath: local))
            try require(actual == Data(original.utf8) && URL(fileURLWithPath: local).lastPathComponent == "seed.xyz", "Persistent file cache changed XYZ bytes or filename")
            connection.disconnect()
            _ = try await connection.request(["action":"list", "path":directory.path], profile: profile)
            try require(startups == 2, "Explicit disconnect did not establish a new channel on demand")
            print("REMOTE_SESSION_PASS: native persistent transport used one helper for parent, child, error recovery and exact XYZ bytes; no SSH authentication or computation in this loopback test.")
            fflush(stdout); exit(0)
        } catch { print("REMOTE_SESSION_FAIL: \(error)"); fflush(stdout); exit(1) }
    }
}
