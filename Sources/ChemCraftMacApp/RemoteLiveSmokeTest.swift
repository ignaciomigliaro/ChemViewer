import AppKit
import ChemCraftCore
import Foundation

/// Opt-in live acceptance against a separately staged, synthetic H2 fixture.
@MainActor
enum RemoteLiveSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        let remote = RemoteConnection.shared
        do {
            let evidence = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/chemviewer-remote-evidence/live-fixture.json")
            let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: evidence)) as! [String: Any]
            let profile = try JSONDecoder().decode(RemoteProfile.self, from: JSONSerialization.data(withJSONObject: metadata["profile"]!))
            let path = metadata["path"] as! String
            let listing = try await remote.request(["action":"list", "path":path], profile: profile)
            let entries = try JSONDecoder().decode([RemoteConnection.Entry].self, from: JSONSerialization.data(withJSONObject: listing["entries"]!))
            guard entries.contains(where: { $0.name == "seed.xyz" }) else { throw ParseError.malformed("Live directory omitted synthetic XYZ") }
            let read = try await remote.request(["action":"read", "path":path + "/seed.xyz"], profile: profile)
            guard read["sha256"] as? String == metadata["sha256"] as? String, let local = read["local"] as? String else { throw ParseError.malformed("Live transfer checksum mismatch") }
            workspace.open(URL(fileURLWithPath: local))
            for _ in 0..<100 {
                if workspace.currentFrame?.atoms.count == 2 { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard let frame = workspace.currentFrame, frame.atoms.count == 2, frame.atoms.allSatisfy({ $0.element == "H" }), abs((frame.atoms[1].position - frame.atoms[0].position).length - 0.74) < 1e-5 else { throw ParseError.malformed("Live H2 contents did not reach the molecular viewer") }
            print("REMOTE_LIVE_PASS: bundled SSH helper browsed ORCD, cached SHA-256 matched staged source, native parser/viewer loaded H2 with 0.74 Å separation. No calculation submitted.")
            fflush(stdout); exit(0)
        } catch { print("REMOTE_LIVE_FAIL: \(error)"); fflush(stdout); exit(1) }
    }
}
