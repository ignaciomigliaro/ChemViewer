import AppKit
import ChemCraftCore
import Foundation

@MainActor
enum RemoteTreeSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        let remote = RemoteConnection.shared
        let defaults = UserDefaults.standard
        let saved = defaults.data(forKey:"ChemViewerSSHProfiles")
        let shown = defaults.object(forKey:"ChemViewerRemoteExplorerVisible")
        func restore() {
            if let saved { defaults.set(saved,forKey:"ChemViewerSSHProfiles") } else { defaults.removeObject(forKey:"ChemViewerSSHProfiles") }
            if let shown { defaults.set(shown,forKey:"ChemViewerRemoteExplorerVisible") } else { defaults.removeObject(forKey:"ChemViewerRemoteExplorerVisible") }
        }
        func require(_ value: Bool,_ message:String) throws { if !value { throw ParseError.malformed(message) } }
        func settle() async throws {
            for _ in 0..<600 { if !remote.busy { break }; try await Task.sleep(nanoseconds:50_000_000) }
            try require(!remote.busy,"Remote explorer request timed out")
            if let active = workspace.documents?.activeWorkspace {
                for _ in 0..<200 { if !active.isLoading { break }; try await Task.sleep(nanoseconds:30_000_000) }
                try require(active.errorMessage == nil,"Remote document failed: \(active.errorMessage ?? "")")
            }
            try await Task.sleep(nanoseconds:150_000_000)
        }
        do {
            let folder=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/chemviewer-remote-evidence")
            let metadata=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("live-fixture.json"))) as! [String:Any]
            var profile=try JSONDecoder().decode(RemoteProfile.self,from:JSONSerialization.data(withJSONObject:metadata["profile"]!))
            let path=metadata["path"] as! String
            profile.directory=path;remote.profile=profile
            remote.clearExplorer();remote.loadExplorerFolder(path,makeRoot:true)
            try await settle()
            try require(remote.explorerVisible && remote.explorerNodes[path]?.contains(where:{$0.name=="molecule.inp"}) == true,"Persistent explorer did not populate")
            remote.toggleExplorerFolder(path+"/templates",expanded:true);try await settle()
            try require(remote.explorerNodes[path+"/templates"]?.contains(where:{$0.name=="step1.inp"}) == true,"Folder expansion failed")
            let initial=workspace.documents!.files.count
            remote.perform("read",path:path+"/seed.xyz",workspace:workspace);try await settle()
            let xyz=workspace.documents!.activeWorkspace
            try require(xyz.currentFrame?.atoms.count==2 && workspace.documents!.files.count==initial+1,"Remote XYZ did not open in a new tab")
            remote.perform("read",path:path+"/molecule.inp",workspace:workspace);try await settle()
            let input=workspace.documents!.activeWorkspace
            try require(input.document?.sourceFormat=="ORCA input" && input.currentFrame?.atoms.count==2,"Remote ORCA xyzfile companion was not resolved")
            try require(abs(input.currentFrame!.atoms[1].position.z - 0.74)<1e-6 && input.document!.energyRecords.isEmpty,"Remote input changed coordinates or inferred energies")
            try require(!xyz.isVibrating && remote.presented==false,"Explorer required a modal or kept inactive XYZ animation running")
            let count=workspace.documents!.files.count
            let origin=RemoteFileOrigin(profile:profile,path:path+"/seed.xyz")
            try require(workspace.documents!.selectExisting(origin:origin) && workspace.documents!.files.count==count,"Selecting an open remote file duplicated its tab")
            workspace.documents!.activate(input.documentIdentity)
            try await Task.sleep(nanoseconds:350_000_000)
            if let window=NSApp.windows.first(where:{$0.isVisible && $0.sheetParent==nil}),let image=CGWindowListCreateImage(.null,.optionIncludingWindow,CGWindowID(window.windowNumber),[.boundsIgnoreFraming,.bestResolution]),let png=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) {try png.write(to:folder.appendingPathComponent("persistent-explorer-tabs.png"))}
            print("REMOTE_TREE_PASS: live persistent explorer/root and folder expansion, remote XYZ plus ORCA xyzfile/companion in separate tabs, exact 0.74 Å geometry/no inferred energies, existing-file dedup, no modal requirement, inactive animation pause; no jobs submitted.")
            restore();remote.disconnect();fflush(stdout);exit(0)
        } catch {restore();remote.disconnect();print("REMOTE_TREE_FAIL: \(error)");fflush(stdout);exit(1)}
    }
}
