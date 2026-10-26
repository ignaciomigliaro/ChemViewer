import AppKit
import ChemCraftCore
import SwiftUI

@MainActor
enum BosTMCSmokeTest {
    static var started=false
    static func run(workspace: WorkspaceStore) async {
        guard !started else{return};started=true
        let model=BosTMCStore.shared,defaults=UserDefaults.standard
        let oldCatalogRemote=defaults.object(forKey:"BossTMCCatalogRemote"),oldFilesRemote=defaults.object(forKey:"BossTMCFilesRemote")
        let oldCSV=defaults.object(forKey:"BossTMCCSV"),oldRoot=defaults.object(forKey:"BossTMCRoot"),oldCache=defaults.object(forKey:"BossTMCCache")
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("chemviewer-bostmc-"+UUID().uuidString)
        func restore(){model.invalidate();for (key,value) in [("BossTMCCatalogRemote",oldCatalogRemote),("BossTMCFilesRemote",oldFilesRemote)]{if let value{defaults.set(value,forKey:key)}else{defaults.removeObject(forKey:key)}};if let oldCSV{defaults.set(oldCSV,forKey:"BossTMCCSV")}else{defaults.removeObject(forKey:"BossTMCCSV")};if let oldRoot{defaults.set(oldRoot,forKey:"BossTMCRoot")}else{defaults.removeObject(forKey:"BossTMCRoot")};if let oldCache{defaults.set(oldCache,forKey:"BossTMCCache")}else{defaults.removeObject(forKey:"BossTMCCache")}}
        func pause() async {try? await Task.sleep(nanoseconds:100_000_000)}
        func require(_ value:Bool,_ message:String) throws {if !value{throw ParseError.malformed(message)}}
        defer{restore();try? FileManager.default.removeItem(at:directory)}
        do{
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            // Start with a loaded document. An empty initial tab is intentionally
            // reused by DocumentTabs; counting it as a newly added tab is wrong.
            let existingURL=directory.appendingPathComponent("existing.xyz")
            try "2\nIndependent existing document\nH 0 0 0\nH 0 0 .74\n".write(to:existingURL,atomically:true,encoding:.utf8)
            let existing=workspace.documents!.open(existingURL)
            for _ in 0..<100{if !existing.isLoading{break};await pause()}
            try require(existing.currentFrame?.atoms.count==2,"Synthetic baseline document failed to load")
            let xyz="7\nIndependent synthetic FeN6 GUI fixture\nFe 0 0 0\nN 2 0 0\nN -2 0 0\nN 0 2 0\nN 0 -2 0\nN 0 0 2\nN 0 0 -2\n"
            for spin in ["singlets","triplets"]{
                let folder=directory.appendingPathComponent(spin+"/HUNJAE_comp_0");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                let geometry = spin == "triplets" ? xyz.replacingOccurrences(of:"N 0 0 2",with:"O 0 0 2").replacingOccurrences(of:"N 0 0 -2",with:"S 0 0 -2") : xyz
                try geometry.write(to:folder.appendingPathComponent("structure.xyz"),atomically:true,encoding:.utf8)
                try "Synthetic Psi4 source fixture; no actual calculation.\nCSV descriptors are separate.\n".write(to:folder.appendingPathComponent("psi4.dat"),atomically:true,encoding:.utf8)
            }
            let csv="refcode,xyz,spinmult,metal,charge,geometry,coordination_number,electronic_energy_Eh,energetic_gap_eV,metal_ligand_bond_lengths,coordinating_atoms\nHUNJAE_comp_0,structure.xyz,1,Fe,2,octahedral,6,-100.123456789012,1.5,\"[2.0,2.0,2.0,2.0,2.0,2.0]\",\"['N','N','N','N','N','N']\"\nHUNJAE_comp_0,structure.xyz,3,Fe,2,octahedral,6,-100.0,0.5,\"[2.0,2.0,2.0,2.0,2.0,2.0]\",\"['N','N','N','N','O','S']\"\n"
            let file=directory.appendingPathComponent("catalog.csv");try csv.write(to:file,atomically:true,encoding:.utf8)
            model.remote=false;model.filesRemote=false;model.csvPath=file.path;model.rootPath=directory.path;model.cachePath=directory.appendingPathComponent("index-cache").path;workspace.activeTab="BosTMC"
            for _ in 0..<4{await pause()};model.index()
            for _ in 0..<300{if !model.busy && model.validCatalog && model.rows.count==2{break};await pause()}
            try require(model.rows.count==2 && model.matched==2,"Native catalog failed to index/query: "+model.status)
            model.filters=[.init(property:"coordinating_atom",mode:"elements_all")]
            for _ in 0..<4{await pause()}
            func descendants(_ view:NSView)->[NSView] { [view]+view.subviews.flatMap{descendants($0)} }
            func buttons()->[NSButton] { NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap{descendants($0)}.compactMap{$0 as? NSButton} }
            guard let anchor=buttons().first(where:{$0.identifier?.rawValue=="bostmc-coordinating-atoms"}) else {throw ParseError.malformed("Coordinating-atom dropdown missing")}
            anchor.performClick(nil)
            for _ in 0..<6{await pause()}
            let elementButtons=buttons().filter{$0.identifier?.rawValue.hasPrefix("periodic-element-")==true}
            try require(elementButtons.count==118,"Coordinating-atom dropdown must expose 118 elements")
            for symbol in ["N","O","Na","Na"] {
                guard let button=elementButtons.first(where:{$0.identifier?.rawValue=="periodic-element-"+symbol}) else {throw ParseError.malformed("Coordinating-atom button missing")}
                button.performClick(nil);await pause()
            }
            try require(model.filters[0].elements==["N","O"] && elementButtons[0].window?.isVisible==true,"Periodic multi-selection dismissed early or failed toggle semantics")
            try require(try model.filters[0].payload()["elements"] as? [String]==["N","O"],"Donor filter payload lost the selected elements")
            if let popup=elementButtons[0].window {
                let evidence=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/chemviewer-bostmc-evidence")
                try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
                if let content=popup.contentView,let bitmap=content.bitmapImageRepForCachingDisplay(in:content.bounds) {
                    content.cacheDisplay(in:content.bounds,to:bitmap)
                    if let png=bitmap.representation(using:.png,properties:[:]) {try png.write(to:evidence.appendingPathComponent("coordinating-atoms.png"))}
                }
                if let escape=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:popup.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53) {popup.sendEvent(escape)}
            }
            for _ in 0..<4{await pause()}
            try require(elementButtons[0].window?.isVisible != true,"Escape did not dismiss the coordinating-atom dropdown")
            model.query(reset:true)
            for _ in 0..<100{if !model.busy{break};await pause()}
            try require(model.matched==1 && model.rows.first?.values["spinmult"]=="3","Required donor subset did not allow additional S or exclude N-only record")
            model.filters=[.init(property:"metal",mode:"exact",text:"Fe"),.init(property:"energetic_gap_eV",mode:"range",lower:"1.0",upper:"2.0")]
            model.query(reset:true)
            for _ in 0..<100{if !model.busy{break};await pause()}
            try require(model.matched==1 && model.rows.first?.values["spinmult"]=="1","Native filters combined spin records or wrong ranges")
            model.select(model.rows[0].id)
            for _ in 0..<100{if !model.selecting{break};await pause()}
            try require(model.frame?.atoms.count==7 && model.frame?.atoms[0].element=="Fe","Candidate XYZ preview failed: "+model.selectionStatus)
            try require(abs(model.frame!.atoms[1].position.x-2)<1e-6 && model.details["electronic_energy_Eh"]=="-100.123456789012","Preview coordinates or raw energy precision changed")
            guard let source=model.files.first(where:{$0.kind=="dat"}) else{throw ParseError.malformed("Associated Psi4 .dat not located")}
            model.openSource(source)
            for _ in 0..<100{if model.sourcePresented{break};await pause()}
            try require(model.sourceText.contains("Synthetic Psi4 source"),"Psi4 raw source viewer failed")
            model.sourcePresented=false
            let evidence=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/chemviewer-bostmc-evidence")
            try FileManager.default.createDirectory(at:evidence,withIntermediateDirectories:true)
            for _ in 0..<4{await pause()}
            if let window=NSApp.windows.first(where:{$0.isVisible && $0.sheetParent==nil}),let image=CGWindowListCreateImage(.null,.optionIncludingWindow,CGWindowID(window.windowNumber),[.boundsIgnoreFraming,.bestResolution]),let png=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]){try png.write(to:evidence.appendingPathComponent("bostmc-native.png"))}
            let count=workspace.documents!.files.count
            model.openInViewer(workspace)
            for _ in 0..<100{if !workspace.documents!.activeWorkspace.isLoading && workspace.documents!.activeWorkspace.charge==2{break};await pause()}
            try require(workspace.documents!.files.count==count+1 && workspace.documents!.activeWorkspace.currentFrame?.atoms.count==7,"Selected XYZ failed to open as an independent document tab")
            try require(workspace.documents!.activeWorkspace.charge==2 && workspace.documents!.activeWorkspace.multiplicity==1,"CSV charge/spin did not follow the geometry")
            model.openInViewer(workspace);try require(workspace.documents!.files.count==count+1,"Reopening the same catalog record duplicated its tab")
            model.select(2)
            for _ in 0..<100{if !model.selecting{break};await pause()}
            model.openInViewer(workspace)
            for _ in 0..<100{if !workspace.documents!.activeWorkspace.isLoading && workspace.documents!.activeWorkspace.multiplicity==3{break};await pause()}
            try require(workspace.documents!.files.count==count+2 && workspace.documents!.activeWorkspace.multiplicity==3,"Distinct spin record did not retain an independent document and multiplicity")
            try require(existing.currentFrame?.atoms.count==2 && existing.currentFrame?.atoms[1].position.z==0.74,"Catalog opening replaced the existing document")
            try require(try String(contentsOf:file,encoding:.utf8)==csv,"Catalog source CSV was modified")
            restore();try? FileManager.default.removeItem(at:directory);print("BOSTMC_PASS: 118-element multi-select, N/O subset with extra donors, exact N/Na toggles, native catalog indexing, AND filters, separate spin records, 7-atom XYZ preview/exact coordinates, full CSV energy precision, associated Psi4 source sheet, independent/deduplicated viewer tabs, CSV charge/spin propagation and separate triplet document, unchanged source CSV. Synthetic fixtures only.");fflush(stdout);exit(0)
        }catch{restore();try? FileManager.default.removeItem(at:directory);print("BOSTMC_FAIL: \(error)");fflush(stdout);exit(1)}
    }
}
