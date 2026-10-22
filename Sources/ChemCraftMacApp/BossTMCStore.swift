import AppKit
import ChemCraftCore
import CryptoKit
import SwiftUI

@MainActor
final class BossTMCStore: ObservableObject {
    static let shared = BossTMCStore()
    static let numericProperties = Set("charge spinmult electronic_energy_Eh dipole_magnitude_debye alpha_HOMO_Eh beta_HOMO_Eh alpha_LUMO_Eh beta_LUMO_Eh alpha_gap_Eh beta_gap_Eh spin_contamination mw natoms ox_state metal_lowdin_charge metal_lowdin_spin metal_mulliken_charge metal_mulliken_spin energetic_gap_eV IS-LS_VSSE_kcal_mol HS-LS_VSSE_kcal_mol HS-IS_VSSE_kcal_mol atomization_energy_Eh relative_AE_kcal_g csd_r_factor metal_index coordination_number".split(separator:" ").map(String.init))
    struct Candidate: Identifiable { let id: Int; let values: [String:String] }
    struct CatalogFile: Identifiable { var id: String { path }; let name: String; let path: String; let kind: String }
    struct Criterion: Identifiable {
        let id = UUID()
        var property: String
        var mode = "range"
        var lower = "", upper = "", text = ""
        func payload() throws -> [String:Any] {
            var result: [String:Any] = ["property":property,"mode":mode]
            if mode == "contains" || mode == "exact" { result["text"] = text }
            if ["range","any","all","mean","min","max"].contains(mode) {
                for (key,value) in [("lower",lower),("upper",upper)] where !value.trimmingCharacters(in:.whitespaces).isEmpty {
                    guard let number = Double(value.replacingOccurrences(of:"D",with:"E").replacingOccurrences(of:"d",with:"e")),number.isFinite else { throw ParseError.malformed("Enter a finite number for \(property).") }
                    result[key] = number
                }
                if result["lower"] == nil && result["upper"] == nil { throw ParseError.malformed("Enter a range limit for \(property).") }
            }
            return result
        }
    }
    @Published var remote = UserDefaults.standard.bool(forKey:"BossTMCCatalogRemote")
    @Published var filesRemote = UserDefaults.standard.object(forKey:"BossTMCFilesRemote") as? Bool ?? true
    @Published var summary: [String:[String:Double]] = [:]
    @Published var categories: [String:[String]] = [:]
    struct HistogramBin: Identifiable {var id:Double{lower};let lower:Double;let upper:Double;let count:Double}
    @Published var histogram: [HistogramBin] = []
    @Published var graphProperty = "energetic_gap_eV"
    @Published var graphStatus = ""
    private var graphGeneration = 0
    private var graphCache: [String:[HistogramBin]] = [:]
    @Published var csvPath: String = {
        let defaults=UserDefaults.standard,saved=UserDefaults.standard.string(forKey:"BossTMCCSV") ?? ""
        if !saved.isEmpty && (defaults.bool(forKey:"BossTMCCatalogRemote") || FileManager.default.fileExists(atPath:saved)){return saved}
        let local=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/BosTMC/BOSTMC-complete.csv").path
        return FileManager.default.fileExists(atPath:local) ? local:saved
    }()
    @Published var rootPath = UserDefaults.standard.string(forKey:"BossTMCRoot") ?? ""
    @Published var cachePath = UserDefaults.standard.string(forKey:"BossTMCCache") ?? ""
    @Published var headers: [String] = []
    @Published var rows: [Candidate] = []
    @Published var total = 0
    @Published var matched = 0
    @Published var offset = 0
    @Published var selectedID: Int?
    @Published var details: [String:String] = [:]
    @Published var files: [CatalogFile] = []
    @Published var frame: MoleculeFrame?
    @Published var previewSelection: [Int] = []
    @Published var xyzURL: URL?
    private var xyzOrigin: RemoteFileOrigin?
    @Published var busy = false
    @Published var selecting = false
    @Published var status = "Choose the dataset CSV and the root containing the spin-state folders."
    @Published var selectionStatus = "Select a candidate to inspect its properties and structure."
    @Published var search = ""
    @Published var filters: [Criterion] = []
    @Published var sort = "refcode"
    @Published var descending = false
    @Published var columns = ["refcode","metal","ox_state","spinmult","geometry","coordination_number","energetic_gap_eV"]
    @Published var sourceText = ""
    @Published var sourceTitle = ""
    @Published var sourcePresented = false
    private var generation = 0, selectionGeneration = 0
    private var polling: Task<Void,Never>?
    private var loadedKey = ""
    private var key: String { "\(remote ? RemoteConnection.shared.explorerIdentity : "local")\0\(csvPath)\0\(rootPath)\0\(cachePath)" }
    var validCatalog: Bool { !headers.isEmpty && loadedKey == key }
    func invalidate() {
        generation += 1; selectionGeneration += 1; polling?.cancel(); polling = nil
        headers=[];rows=[];details=[:];frame=nil;files=[];xyzURL=nil;xyzOrigin=nil;selectedID=nil;busy=false;selecting=false
        summary=[:];categories=[:];histogram=[];graphCache=[:];graphGeneration += 1
        status="Dataset location changed. Index CSV to load its catalog."
    }
    func request(_ action: String, extras: [String:Any] = [:]) async throws -> [String:Any] {
        var payload: [String:Any] = ["action":action,"csv":csvPath,"root":rootPath]
        if !cachePath.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{payload["cache_dir"]=cachePath}
        payload.merge(extras) { _,new in new }
        if remote {
            let connection=RemoteConnection.shared, profile=RemoteConnection.shared.profile
            guard !profile.host.isEmpty else { throw ParseError.malformed("Choose an SSH connection first.") }
            while connection.busy { try await Task.sleep(nanoseconds:50_000_000) }
            guard profile.host == connection.profile.host && profile.python == connection.profile.python && profile.setup == connection.profile.setup else { throw ParseError.malformed("SSH settings changed. Retry on the selected host.") }
            connection.busy=true;defer{connection.busy=false}
            return try await connection.request(payload,profile:profile)
        }
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("bostmc-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:directory)}
        let input=directory.appendingPathComponent("request.json"),output=directory.appendingPathComponent("response.json")
        try JSONSerialization.data(withJSONObject:payload).write(to:input)
        let job=Process();job.executableURL=FileManager.default.isExecutableFile(atPath:ChemistryRuntime.python.path) ? ChemistryRuntime.python:URL(fileURLWithPath:"/usr/bin/python3")
        job.arguments=[ChemistryResources.bundle.url(forResource:"bostmc_catalog",withExtension:"py")!.path,input.path,output.path]
        job.standardInput=FileHandle.nullDevice;job.standardOutput=FileHandle.nullDevice;job.standardError=FileHandle.nullDevice;try job.run()
        let code=await Task.detached{job.waitUntilExit();return job.terminationStatus}.value
        guard code==0,let response=try JSONSerialization.jsonObject(with:Data(contentsOf:output)) as? [String:Any] else{throw ParseError.malformed("Catalog helper failed.")}
        guard response["ok"] as? Bool==true else{throw ParseError.malformed(response["error"] as? String ?? "Catalog request failed.")}
        return response["result"] as? [String:Any] ?? [:]
    }
    func index() {
        guard !busy,!csvPath.isEmpty else{return}
        invalidate();busy=true;let token=generation,identity=key
        UserDefaults.standard.set(remote,forKey:"BossTMCCatalogRemote");UserDefaults.standard.set(filesRemote,forKey:"BossTMCFilesRemote")
        UserDefaults.standard.set(csvPath,forKey:"BossTMCCSV");UserDefaults.standard.set(rootPath,forKey:"BossTMCRoot");UserDefaults.standard.set(cachePath,forKey:"BossTMCCache")
        status="Starting a streaming index on \(remote ? RemoteConnection.shared.profile.host : "this Mac")…"
        polling=Task {
            do {
                var result=try await request("bostmc-start")
                while token==generation && identity==key && !Task.isCancelled {
                    switch result["phase"] as? String {
                    case "ready":
                        summary=(result["summary"] as? [String:[String:Any]] ?? [:]).mapValues{raw in raw.compactMapValues{($0 as? NSNumber)?.doubleValue}}
                        categories=(result["categories"] as? [String:[[String:Any]]] ?? [:]).mapValues{$0.compactMap{$0["value"] as? String}}
                        headers=result["headers"] as? [String] ?? [];total=result["total"] as? Int ?? 0
                        columns=columns.filter{headers.contains($0)};if columns.isEmpty{columns=Array(headers.prefix(6))}
                        filters=filters.filter{headers.contains($0.property)};loadedKey=identity;busy=false
                        status="Indexed \(total.formatted()) records. Source values and units are preserved."
                        query(reset:true);loadGraph();return
                    case "error":throw ParseError.malformed(result["error"] as? String ?? "Indexing failed.")
                    default:status="Indexing CSV on source host · \((result["rows"] as? Int ?? 0).formatted()) records…"
                    }
                    try await Task.sleep(nanoseconds:750_000_000);result=try await request("bostmc-status")
                }
            }catch{if token==generation{busy=false;status=error.localizedDescription}}
        }
    }
    func query(reset: Bool=false) {
        guard validCatalog,!busy else{return}
        if reset{offset=0};generation += 1;let token=generation;busy=true
        Task {
            defer{if token==generation{busy=false}}
            do {
                let criteria=try filters.map{try $0.payload()}
                let result=try await request("bostmc-query",extras:["filters":criteria,"search":search,"sort":sort,"descending":descending,"offset":offset,"columns":Array(Set(columns+["refcode"]))])
                guard token==generation else{return}
                matched=result["total"] as? Int ?? 0
                rows=(result["rows"] as? [[String:Any]] ?? []).map{raw in Candidate(id:raw["__id"] as! Int,values:raw.reduce(into:[:]){if let value=$1.value as? String{$0[$1.key]=value}})}
                status="\(matched.formatted()) of \(total.formatted()) records match · all criteria combined with AND."
                if let id=selectedID,!rows.contains(where:{$0.id==id}){selectionGeneration += 1;selecting=false;selectedID=nil;details=[:];files=[];frame=nil;xyzURL=nil;xyzOrigin=nil}
            }catch{if token==generation{status=error.localizedDescription}}
        }
    }
    func select(_ id: Int) {
        selectedID=id;selectionGeneration += 1;let token=selectionGeneration,identity=key
        selecting=true;details=[:];files=[];frame=nil;xyzURL=nil;xyzOrigin=nil;previewSelection=[]
        selectionStatus="Loading candidate properties and locating source files…"
        Task {
            defer{if token==selectionGeneration{selecting=false}}
            do {
                let result=try await request("bostmc-detail",extras:["id":id]);guard token==selectionGeneration,identity==key else{return}
                details=result["values"] as? [String:String] ?? [:]
                let found: [String:Any]
                if let inline=details["xyz"],inline.trimmingCharacters(in:.whitespacesAndNewlines).first?.isNumber==true,inline.contains("\n"){found=["inline_xyz":inline,"files":[]]}
                else{found=try await resolveFiles(id:id)}
                guard token==selectionGeneration,identity==key else{return}
                files=(found["files"] as? [[String:String]] ?? []).compactMap{d in guard let name=d["name"],let path=d["path"],let kind=d["kind"] else{return nil};return CatalogFile(name:name,path:path,kind:kind)}
                let url: URL
                if let inline=found["inline_xyz"] as? String {
                    let hash=SHA256.hash(data:Data((identity+String(id)).utf8)).map{String(format:"%02x",$0)}.joined()
                    let folder=FileManager.default.temporaryDirectory.appendingPathComponent("BossTMC-inline-"+hash);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                    url=folder.appendingPathComponent("structure.xyz");try inline.write(to:url,atomically:true,encoding:.utf8)
                }else{
                    guard let xyz=files.first(where:{$0.kind=="xyz"}) else{selectionStatus="No XYZ found. Check the dataset root or inspect the CSV xyz field.";return}
                    url=try await cachedFile(xyz.path)
                }
                let parsed=try await Task.detached{try ParserRegistry.parse(url:url)}.value
                guard token==selectionGeneration,identity==key else{return}
                if (remote || filesRemote),found["inline_xyz"] == nil,let xyz=files.first(where:{$0.kind=="xyz"}){xyzOrigin=RemoteFileOrigin(profile:RemoteConnection.shared.profile,path:xyz.path)}
                xyzURL=url;frame=parsed.frames.first;selectionStatus="\(details["refcode"] ?? "") · geometry from XYZ; descriptors from CSV." + (files.filter{$0.kind=="xyz"}.count>1 ? " Multiple XYZ files: use XYZ geometry to choose.":"")
            }catch{if token==selectionGeneration{selectionStatus=error.localizedDescription}}
        }
    }
    func previewGeometry(_ file: CatalogFile) {
        selectionGeneration += 1;let token=selectionGeneration,identity=key;selecting=true;xyzURL=nil;xyzOrigin=nil;frame=nil
        Task {
            defer{if token==selectionGeneration{selecting=false}}
            do{let url=try await cachedFile(file.path);let document=try await Task.detached{try ParserRegistry.parse(url:url)}.value
                guard token==selectionGeneration,identity==key else{return};frame=document.frames.first;xyzURL=url;previewSelection=[]
                xyzOrigin=(remote || filesRemote) ? RemoteFileOrigin(profile:RemoteConnection.shared.profile,path:file.path):nil
                selectionStatus="Previewing \(file.name) · descriptor values remain from the selected CSV record."
            }catch{if token==selectionGeneration{selectionStatus=error.localizedDescription}}
        }
    }
    func resolveFiles(id: Int) async throws -> [String:Any] {
        if (remote || filesRemote) && rootPath.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{throw ParseError.malformed("Choose the remote dataset root containing the spin-state folders before locating SSH files.")}
        if remote || !filesRemote{return try await request("bostmc-files",extras:["id":id])}
        let xyz=details["xyz"] ?? ""
        let record=["refcode":details["refcode"] ?? "","spinmult":details["spinmult"] ?? "","xyz":xyz.contains("\n") ? "":xyz]
        return try await remoteFilesRequest(["action":"bostmc-resolve","record":record,"root":rootPath])
    }
    private func remoteFilesRequest(_ payload: [String:Any]) async throws -> [String:Any] {
        let connection=RemoteConnection.shared,profile=RemoteConnection.shared.profile
        guard !profile.host.isEmpty else{throw ParseError.malformed("Choose an SSH connection for structure/output files.")}
        while connection.busy{try await Task.sleep(nanoseconds:50_000_000)}
        guard profile.host==connection.profile.host,profile.python==connection.profile.python,profile.setup==connection.profile.setup else{throw ParseError.malformed("SSH connection changed.")}
        connection.busy=true;defer{connection.busy=false}
        return try await connection.request(payload,profile:profile)
    }
    func findAssociatedFiles() {
        guard let id=selectedID,!selecting else{return};let token=selectionGeneration;selecting=true
        Task{defer{if token==selectionGeneration{selecting=false}}
            do{let found=try await resolveFiles(id:id);guard token==selectionGeneration else{return}
                files=(found["files"] as? [[String:String]] ?? []).compactMap{d in guard let name=d["name"],let path=d["path"],let kind=d["kind"] else{return nil};return CatalogFile(name:name,path:path,kind:kind)}
                selectionStatus=files.isEmpty ? "No associated files found. Check the structure root.":"Located \(files.count) associated source files."
            }catch{if token==selectionGeneration{selectionStatus=error.localizedDescription}}
        }
    }
    func loadGraph() {
        graphGeneration += 1;let token=graphGeneration,property=graphProperty
        if let cached=graphCache[property]{histogram=cached;graphStatus="Full catalog · finite values only";return}
        histogram=[];graphStatus="Loading distribution…"
        guard validCatalog,Self.numericProperties.contains(property) else{return}
        Task{do{let result=try await request("bostmc-histogram",extras:["property":property]);guard token==graphGeneration else{return}
            histogram=(result["bins"] as? [[String:Double]] ?? []).compactMap{d in guard let lo=d["lower"],let hi=d["upper"],let n=d["count"] else{return nil};return HistogramBin(lower:lo,upper:hi,count:n)}
            graphCache[property]=histogram;graphStatus="Full catalog · \(Int(result["count"] as? Double ?? 0).formatted()) finite values"
        }catch{if token==graphGeneration{graphStatus=error.localizedDescription}}}
    }
    func cachedFile(_ path: String) async throws -> URL {
        if !remote && !filesRemote{return URL(fileURLWithPath:(path as NSString).expandingTildeInPath)}
        let connection=RemoteConnection.shared,profile=RemoteConnection.shared.profile
        while connection.busy{try await Task.sleep(nanoseconds:50_000_000)}
        guard profile.host == connection.profile.host && profile.python == connection.profile.python && profile.setup == connection.profile.setup else{throw ParseError.malformed("SSH settings changed.")}
        connection.busy=true;defer{connection.busy=false}
        let result=try await connection.request(["action":"read","path":path],profile:profile)
        guard let local=result["local"] as? String else{throw ParseError.malformed("Remote file transfer failed.")}
        return URL(fileURLWithPath:local)
    }
    func openInViewer(_ workspace: WorkspaceStore) {
        guard let xyzURL,let recordID=selectedID else{return}
        let source=details
        func integer(_ key: String) -> Int? {
            guard let number=Double(source[key] ?? ""),number.isFinite,abs(number)<=Double(Int32.max),number.rounded()==number else{return nil}
            return Int(number)
        }
        guard let spin=integer("spinmult"),spin>0 else{selectionStatus="The CSV spin multiplicity must be a positive integer before opening this candidate.";return}
        let charge=integer("charge")
        let suffix="#BossTMC:"+SHA256.hash(data:Data((key+String(recordID)).utf8)).map{String(format:"%02x",$0)}.joined()
        let target: WorkspaceStore
        if let documents=workspace.documents{target=documents.open(xyzURL,origin:xyzOrigin,identitySuffix:suffix)}else{target=workspace;target.open(xyzURL)}
        let epoch=target.viewportEpoch
        target.activeTab="Image"
        Task {
            while target.isLoading{try? await Task.sleep(nanoseconds:25_000_000)}
            guard target.viewportEpoch==epoch,target.document != nil,!target.hasUnsavedDocumentChanges else{return}
            target.multiplicity=spin;target.document?.multiplicity=spin
            if let charge{target.charge=charge;target.document?.charge=charge}
            target.document?.title=(source["refcode"] ?? xyzURL.lastPathComponent)+" · mult \(spin)"
            let provenance="BossTMC CSV record \(recordID): multiplicity \(spin)"+(charge.map{" and charge \($0)"} ?? "; charge missing/invalid—set it before calculation")+". Descriptors remain sourced from the CSV."
            if target.document?.warnings.contains(provenance) != true{target.document?.warnings.append(provenance)}
        }
    }
    func openSource(_ file: CatalogFile) {
        let identity=key
        Task {do{let url=try await cachedFile(file.path);let text=try await Task.detached{try String(contentsOf:url,encoding:.utf8)}.value
            guard identity==key else{return};sourceText=String(text.prefix(2_000_000));sourceTitle=file.path;sourcePresented=true
        }catch{selectionStatus=error.localizedDescription}}
    }
    func export() {
        guard validCatalog,!busy else{return}
        let panel=NSSavePanel();panel.nameFieldStringValue="BossTMC-candidates.csv";guard panel.runModal() == .OK,let target=panel.url else{return}
        busy=true;let identity=key
        Task {
            let temporary=target.deletingLastPathComponent().appendingPathComponent(".bostmc-export-"+UUID().uuidString)
            defer{busy=false;try? FileManager.default.removeItem(at:temporary)}
            do {
                FileManager.default.createFile(atPath:temporary.path,contents:nil);let output=try FileHandle(forWritingTo:temporary);defer{try? output.close()}
                let criteria=try filters.map{try $0.payload()};let currentSearch=search;var after=0,count=0
                while true {
                    guard identity==key else{throw CancellationError()}
                    let result=try await request("bostmc-export",extras:["filters":criteria,"search":currentSearch,"after":after])
                    try output.write(contentsOf:Data((result["csv"] as? String ?? "").utf8));count += result["count"] as? Int ?? 0
                    status="Exporting \(count.formatted()) matching records…"
                    if result["done"] as? Bool==true{break};after=result["after"] as! Int
                }
                try output.synchronize();try output.close()
                if FileManager.default.fileExists(atPath:target.path){_ = try FileManager.default.replaceItemAt(target,withItemAt:temporary)}else{try FileManager.default.moveItem(at:temporary,to:target)}
                status="Exported \(count.formatted()) candidates with all source columns."
            }catch{status=error.localizedDescription}
        }
    }
}
