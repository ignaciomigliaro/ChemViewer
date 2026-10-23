import AppKit
import ChemCraftCore
import SwiftUI

/// Read-only acceptance on the user's explicitly supplied local catalog. Never submits or connects SSH.
@MainActor enum BosTMCLocalSmokeTest {
    static var started=false
    static func run(workspace:WorkspaceStore) async {
        guard !started else{return};started=true
        let model=BosTMCStore.shared,defaults=UserDefaults.standard
        let keys=["BossTMCCSV","BossTMCRoot","BossTMCCache","BossTMCCatalogRemote","BossTMCFilesRemote"],saved=keys.map{UserDefaults.standard.object(forKey:$0)}
        func restore(){for (key,value) in zip(keys,saved){if let value{defaults.set(value,forKey:key)}else{defaults.removeObject(forKey:key)}}}
        func pause() async {try? await Task.sleep(nanoseconds:100_000_000)}
        func require(_ value:Bool,_ message:String)throws{if !value{throw ParseError.malformed(message)}}
        do{
            let csv=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/BosTMC/BOSTMC-complete.csv")
            let before=try FileManager.default.attributesOfItem(atPath:csv.path)
            let connection=RemoteConnection.shared.connectionStatus
            model.remote=false;model.filesRemote=true;model.csvPath=csv.path;model.cachePath="";model.rootPath="";workspace.activeTab="BosTMC"
            for _ in 0..<4{await pause()};model.index()
            for _ in 0..<2400{if model.validCatalog && !model.busy && !model.rows.isEmpty{break};await pause()}
            try require(model.total==263235,"Actual catalog row count differs: \(model.status)")
            try require(model.categories["geometry"]?.contains("square planar")==true,"Geometry dropdown values missing")
            try require(model.summary["energetic_gap_eV"]?["count"]==263235,"Numeric slider domain count differs")
            let id=model.rows[0].id;model.select(id)
            for _ in 0..<200{if !model.selecting{break};await pause()}
            try require(model.frame?.atoms.isEmpty==false,"Embedded XYZ preview failed: \(model.selectionStatus)")
            try require(!model.details["alpha_HOMO_Eh",default:""].isEmpty,"Orbital plot data missing")
            for _ in 0..<100{if !model.histogram.isEmpty{break};await pause()}
            try require(Int(model.histogram.reduce(0){$0+$1.count})==263235,"Histogram count oracle failed")
            try require(RemoteConnection.shared.connectionStatus==connection,"Local selection unexpectedly opened SSH")
            model.filters=[.init(property:"geometry",mode:"exact",text:"square planar"),.init(property:"energetic_gap_eV",mode:"range",lower:"1",upper:"3")];model.query(reset:true)
            for _ in 0..<200{if !model.busy{break};await pause()}
            try require(model.matched>0 && model.rows.allSatisfy{$0.values["geometry"]=="square planar"},"Combined local filters failed")
            model.select(model.rows[0].id);for _ in 0..<200{if !model.selecting{break};await pause()}
            for _ in 0..<6{await pause()}
            if let window=NSApp.windows.first(where:{$0.isVisible && $0.sheetParent==nil}),let image=CGWindowListCreateImage(.null,.optionIncludingWindow,CGWindowID(window.windowNumber),[.boundsIgnoreFraming,.bestResolution]),let png=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]){try png.write(to:URL(fileURLWithPath:"/private/tmp/bostmc-local-native.png"))}
            let after=try FileManager.default.attributesOfItem(atPath:csv.path)
            try require(before[.size] as? Int==after[.size] as? Int && before[.modificationDate] as? Date==after[.modificationDate] as? Date,"CSV source changed")
            try await sliderCheck()
            restore();print("BOSTMC_LOCAL_PASS: actual 263235-record catalog; local AND filters, geometry options/numeric domains, inline XYZ preview without SSH, orbital descriptors, histogram population, two native slider-handle drags and unchanged source. Associated HPC output retrieval not tested.");fflush(stdout);exit(0)
        }catch{restore();print("BOSTMC_LOCAL_FAIL: \(error)");fflush(stdout);exit(1)}
    }
    private static func sliderCheck() async throws {
        var low="2",high="8"
        let window=NSWindow(contentRect:NSRect(x:180,y:180,width:320,height:64),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        let host=NSHostingView(rootView:BosTMCRangeSlider(lower:Binding(get:{low},set:{low=$0}),upper:Binding(get:{high},set:{high=$0}),minimum:0,maximum:10).frame(width:280,height:24).padding(20))
        window.contentView=host;window.setContentSize(NSSize(width:320,height:64));window.title="ChemViewer — range slider acceptance";window.makeKeyAndOrderFront(nil)
        defer{window.orderOut(nil);window.contentView=nil}
        NSApp.activate(ignoringOtherApps:true)
        try await Task.sleep(nanoseconds:600_000_000)
        host.layoutSubtreeIfNeeded()
        if let image=CGWindowListCreateImage(.null,.optionIncludingWindow,CGWindowID(window.windowNumber),[.boundsIgnoreFraming,.bestResolution]),let png=NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]){try png.write(to:URL(fileURLWithPath:"/private/tmp/bostmc-slider-before.png"))}
        print("SLIDER_WINDOW",host.frame,host.bounds,window.isKeyWindow,NSApp.isActive);fflush(stdout)
        func point(_ value:Double)->NSPoint {host.convert(NSPoint(x:29+262*value/10,y:32),to:nil)}
        func drag(_ from:Double,_ to:Double) async {
            let kinds:[NSEvent.EventType]=[.leftMouseDown,.leftMouseDragged,.leftMouseUp]
            for (i,kind) in kinds.enumerated(){let event=NSEvent.mouseEvent(with:kind,location:point(i==0 ? from:to),modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,eventNumber:i,clickCount:1,pressure:1)!;window.sendEvent(event);try? await Task.sleep(nanoseconds:80_000_000)}
        }
        await drag(2,4)
        guard let l=Double(low),abs(l-4)<0.15,high=="8" else{throw ParseError.malformed("Minimum slider drag failed: \(low), \(high)")}
        await drag(8,6)
        guard let h=Double(high),abs(h-6)<0.15,Double(low)==l else{throw ParseError.malformed("Maximum slider drag failed: \(low), \(high)")}
    }

}
