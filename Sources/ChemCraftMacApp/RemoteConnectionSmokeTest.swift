import AppKit
import ChemCraftCore
import Foundation

/// Native sheet and bundled transport checks; does not authenticate or submit jobs.
@MainActor
enum RemoteConnectionSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        let remote = RemoteConnection.shared
        let saved = UserDefaults.standard.data(forKey: "ChemViewerSSHProfiles")
        func restore() {
            if let saved { UserDefaults.standard.set(saved, forKey: "ChemViewerSSHProfiles") }
            else { UserDefaults.standard.removeObject(forKey: "ChemViewerSSHProfiles") }
        }
        func require(_ value: Bool, _ message: String) throws { if !value { throw ParseError.malformed(message) } }
        do {
            remote.profile = RemoteProfile(name: "Synthetic cluster", host: "synthetic-test-only", directory: "~/work", python: "~/env/bin/python", setup: "module load python", config: "~/work/input.yaml")
            remote.saveProfile()
            let reopened = RemoteConnection()
            try require(reopened.profiles.contains(remote.profile), "SSH profile settings did not persist")
            let auth = try await remote.request(["action": "authenticate"], profile: remote.profile)
            guard let file = auth["terminal"] as? String else { throw ParseError.malformed("Authentication command missing") }
            let script = try String(contentsOfFile: file)
            try require(script.contains("/usr/bin/ssh -M") && script.contains("-fN synthetic-test-only") && !script.contains("StrictHostKeyChecking=no"), "Interactive SSH command is incorrect")
            try FileManager.default.removeItem(atPath: file)
            // Exercise packaged helper's validation; no connection is attempted for invalid aliases.
            var invalid = remote.profile; invalid.host = "-oProxyCommand=invalid"
            do {
                _ = try await remote.request(["action": "list", "path": "~"], profile: invalid)
                throw ParseError.malformed("Unsafe host accepted")
            } catch let error as RemoteError { try require(error.localizedDescription.contains("SSH alias"), "Invalid-host error not surfaced") }
            remote.entries = [RemoteConnection.Entry(name: "templates", path: "/synthetic/templates", directory: true, size: 0), RemoteConnection.Entry(name: "trajectory.xyz", path: "/synthetic/trajectory.xyz", directory: false, size: 1024), RemoteConnection.Entry(name: "input.yaml", path: "/synthetic/input.yaml", directory: false, size: 500)]
            remote.selected = "/synthetic/trajectory.xyz"
            remote.runSummary = RemoteConnection.summary(["steps": [["step":1,"engine":"orca","reported_survivors":1,"failures":0,"cached":true]], "results": [["step":1,"name":"H2 fixture","results":["rows":[["Conformer":"0","Energy (Hartree)":"-1.116759307204","Energy type":"electronic"]]]]]])
            try require(remote.runSummary.contains("-1.116759307204") && remote.runSummary.contains("Hartree") && remote.runSummary.contains("H2 fixture"), "Result values/units/name were changed")
            remote.log = "Synthetic UI fixture; no SSH login or SLURM job was run."
            remote.status = "Synthetic browser and workflow display acceptance test."
            remote.presented = true
            try await Task.sleep(nanoseconds: 800_000_000)
            guard let sheet = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent != nil }), let content = sheet.contentView else { throw ParseError.malformed("Remote browser sheet did not open") }
            try require(sheet.frame.width >= 1000 && sheet.frame.height >= 650, "Remote controls sheet is clipped")
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/chemviewer-remote-evidence")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(sheet.windowNumber), [.boundsIgnoreFraming, .bestResolution]), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try png.write(to: folder.appendingPathComponent("remote-browser.png"))
            }
            remote.presented = false; restore()
            print("REMOTE_CONNECTION_PASS: native sheet, persisted profiles, bundled auth helper, invalid-host rejection, exact energy units; live SSH/SLURM not tested")
            fflush(stdout); exit(0)
        } catch {
            restore(); print("REMOTE_CONNECTION_FAIL: \(error)"); fflush(stdout); exit(1)
        }
    }
}
