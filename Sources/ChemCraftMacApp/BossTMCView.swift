import AppKit
import ChemCraftCore
import SwiftUI

struct BossTMCView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var catalog = BossTMCStore.shared
    @ObservedObject private var connection = RemoteConnection.shared
    @State private var picker: RemoteWorkflowPicker.Kind?
    @State private var pickingRoot = false
    @State private var configuration = true
    private let modes=[("range","Numeric range"),("exact","Exact text"),("contains","Text contains"),("present","Has a value"),("missing","Missing value"),("any","Any array value"),("all","All array values"),("mean","Array mean"),("min","Array minimum"),("max","Array maximum")]
    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Label("BossTMC · Catalyst candidates",systemImage:"line.3.horizontal.decrease.circle").font(.headline)
                Spacer()
                Picker("Data source",selection:$catalog.remote){Text("SSH / HPC").tag(true);Text("This Mac").tag(false)}.pickerStyle(.segmented).frame(width:220).disabled(catalog.busy)
                Button("Dataset settings"){configuration.toggle()}
                Button("Export candidates…"){catalog.export()}.disabled(!catalog.validCatalog || catalog.busy)
            }.padding(10)
            if configuration {
                VStack(spacing:7) {
                    HStack {
                        Text(catalog.remote ? "SSH: \(connection.profile.host.isEmpty ? "not configured" : connection.profile.host)":"Local CSV index").font(.caption)
                        if catalog.remote{Button("SSH settings…"){connection.presented=true}}
                        Spacer()
                        Text("The source dataset is read-only. Only the CSV index and selected files are cached.").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack{Text("CSV").frame(width:50,alignment:.leading);TextField("Full path to the property CSV",text:$catalog.csvPath);Button("Browse…"){choose(root:false)}}
                    HStack{Text("Index cache").font(.caption).frame(width:70,alignment:.leading);TextField("Optional directory on the source host; default ~/.cache/ChemViewer/BossTMC",text:$catalog.cachePath)}
                    HStack{Text("Root").frame(width:50,alignment:.leading);TextField("Folder containing singlets, doublets, triplets, quartets, quintets, sextets",text:$catalog.rootPath);Button("Browse…"){choose(root:true)};Button("Index CSV"){catalog.index()}.buttonStyle(.borderedProminent).disabled(catalog.csvPath.isEmpty)}
                }.padding(.horizontal,10).padding(.bottom,10).disabled(catalog.busy)
            }
            HStack {
                if catalog.busy{ProgressView().controlSize(.small)}
                Text(catalog.status).font(.caption).textSelection(.enabled)
                Spacer()
            }.padding(.horizontal,10).padding(.bottom,8)
            Divider()
            if !catalog.validCatalog {
                VStack(spacing:12){Image(systemName:"tablecells").font(.system(size:38)).foregroundStyle(.secondary);Text("Screen the dataset by geometry and electronic structure").font(.title2);Text("Index the CSV once on its source computer. Combine property criteria, inspect the matching geometries, then open selected structures in ChemViewer.").multilineTextAlignment(.center).frame(maxWidth:570)}.frame(maxWidth:.infinity,maxHeight:.infinity)
            }else{
                HSplitView {
                    filters.frame(minWidth:245,idealWidth:285,maxWidth:350)
                    VSplitView {
                        candidates.frame(minHeight:180)
                        inspection.frame(minHeight:220)
                    }.frame(minWidth:450)
                }
            }
        }
        .onChange(of:catalog.csvPath){_ in catalog.invalidate()}
        .onChange(of:catalog.rootPath){_ in catalog.invalidate()}
        .onChange(of:catalog.cachePath){_ in catalog.invalidate()}
        .onChange(of:catalog.remote){_ in catalog.invalidate()}
        .onChange(of:connection.explorerIdentity){_ in if catalog.remote{catalog.invalidate()}}
        .sheet(item:$picker){kind in
            RemoteWorkflowPicker(kind:kind, title:pickingRoot ? "Choose BosTMC dataset root":"Choose BosTMC property CSV",buttonTitle:pickingRoot ? "Use folder":"Use CSV") {path in
                if pickingRoot{catalog.rootPath=path}else{catalog.csvPath=path}
            }
        }
        .sheet(isPresented:$catalog.sourcePresented){
            VStack(alignment:.leading){HStack{Text(catalog.sourceTitle).font(.caption).textSelection(.enabled);Spacer();Button("Done"){catalog.sourcePresented=false}};Text("Source text · CSV descriptors are shown separately. Long output is limited to the first 2 million characters.").font(.caption).foregroundStyle(.secondary);SourceTextView(text:catalog.sourceText,focusLine:nil)}.padding(12).frame(minWidth:850,minHeight:580)
        }
    }
    private var filters: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("PROPERTY CRITERIA").font(.caption.bold())
            TextField("Refcode, formula, metal or geometry",text:$catalog.search).textFieldStyle(.roundedBorder).onSubmit{catalog.query(reset:true)}
            Menu("Add property filter") {
                ForEach(catalog.headers,id:\.self){field in Button(field){catalog.filters.append(.init(property:field,mode:BossTMCStore.numericProperties.contains(field) ? "range":"contains"))}}
            }.disabled(catalog.filters.count>=32)
            ScrollView {
                VStack(spacing:12){ForEach($catalog.filters){$criterion in
                    VStack(alignment:.leading,spacing:6){
                        HStack{Text(criterion.property).font(.caption.bold()).lineLimit(2);Spacer();Button{catalog.filters.removeAll{$0.id==criterion.id}}label:{Image(systemName:"xmark")}.buttonStyle(.plain)}
                        Picker("Comparison",selection:$criterion.mode){ForEach(modes,id:\.0){mode in Text(mode.1).tag(mode.0)}}.labelsHidden()
                        if ["contains","exact"].contains(criterion.mode){TextField("Value",text:$criterion.text)}
                        else if !["present","missing"].contains(criterion.mode){HStack{TextField("Minimum",text:$criterion.lower);Text("to");TextField("Maximum",text:$criterion.upper)}}
                    }.padding(8).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:6))
                }}
            }
            Text("All criteria use AND. Ranges are inclusive and use source CSV units. Numeric filters exclude missing/nonfinite values. Array filters apply to numeric entries in lists or dictionary values.").font(.caption).foregroundStyle(.secondary)
            HStack{Button("Apply filters"){catalog.query(reset:true)}.buttonStyle(.borderedProminent);Button("Clear"){catalog.filters=[];catalog.search="";catalog.query(reset:true)}}.disabled(catalog.busy)
        }.padding(10)
    }
    private var candidates: some View {
        VStack(alignment:.leading,spacing:8){
            HStack {
                Text("\(catalog.matched.formatted()) matching candidates").font(.headline)
                Spacer()
                Menu("Columns") {ForEach(catalog.headers,id:\.self){h in Button((catalog.columns.contains(h) ? "✓ ":"")+h){if catalog.columns.contains(h){if catalog.columns.count>1{catalog.columns.removeAll{$0==h}}}else{catalog.columns.append(h)};catalog.query()}}}
                Picker("Sort",selection:$catalog.sort){ForEach(catalog.headers,id:\.self){Text($0).tag($0)}}.frame(maxWidth:240)
                Toggle("Descending",isOn:$catalog.descending).toggleStyle(.checkbox)
                Button("Sort"){catalog.query(reset:true)}.disabled(catalog.busy)
            }
            ScrollView(.horizontal){
                VStack(alignment:.leading,spacing:0){
                    HStack(spacing:0){ForEach(catalog.columns,id:\.self){column in Text(column).font(.caption.bold()).lineLimit(2).frame(width:column=="refcode" ? 175:140,height:35,alignment:.leading)}}.padding(.horizontal,8).background(Color(nsColor:.controlBackgroundColor))
                    ScrollView(.vertical){LazyVStack(spacing:0){ForEach(catalog.rows){row in
                        Button{catalog.select(row.id)}label:{HStack(spacing:0){ForEach(catalog.columns,id:\.self){column in Text(row.values[column].flatMap{$0.isEmpty ? nil:$0} ?? "—").font(.system(size:12,design:.monospaced)).lineLimit(1).frame(width:column=="refcode" ? 175:140,height:29,alignment:.leading).help(row.values[column] ?? "")}}.padding(.horizontal,8).contentShape(Rectangle())}.buttonStyle(.plain).background(catalog.selectedID==row.id ? Color.accentColor.opacity(0.16):Color.clear)
                        Divider()
                    }}}
                }.frame(minWidth:CGFloat(catalog.columns.reduce(0){$0+($1=="refcode" ? 175:140)})+16)
            }
            HStack{Button("Previous"){catalog.offset=max(0,catalog.offset-50);catalog.query()}.disabled(catalog.busy || catalog.offset==0);Text(catalog.matched==0 ? "No matches":"\(catalog.offset+1)–\(catalog.offset+catalog.rows.count) of \(catalog.matched.formatted())").font(.caption);Button("Next"){catalog.offset += 50;catalog.query()}.disabled(catalog.busy || catalog.offset+50>=catalog.matched);Spacer();Text("Spin-state records remain separate.").font(.caption).foregroundStyle(.secondary)}
        }.padding(10)
    }
    private var inspection: some View {
        HSplitView {
            VStack(alignment:.leading,spacing:5){
                HStack{Text(catalog.details["refcode"] ?? "Structure preview").font(.headline);Spacer();if catalog.files.filter({$0.kind=="xyz"}).count>1{Menu("XYZ geometry"){ForEach(catalog.files.filter{$0.kind=="xyz"}){file in Button(file.name){catalog.previewGeometry(file)}}}};Button("Open XYZ in viewer"){catalog.openInViewer(workspace)}.disabled(catalog.xyzURL==nil)}
                if let frame=catalog.frame{MoleculeMetalView(frame:frame,mode:nil,isAnimating:false,amplitude:0,showDisplacementVectors:false,selectedAtomIndices:$catalog.previewSelection).id(catalog.selectedID)}
                else{VStack{if catalog.selecting{ProgressView()};Text("Select a candidate to load its XYZ.").foregroundStyle(.secondary)}.frame(maxWidth:.infinity,maxHeight:.infinity)}
                Text(catalog.selectionStatus).font(.caption).textSelection(.enabled)
            }.padding(10).frame(minWidth:270)
            VStack(alignment:.leading,spacing:8){
                HStack{Text("CSV DESCRIPTORS").font(.caption.bold());Spacer();Button("Copy record"){NSPasteboard.general.clearContents();NSPasteboard.general.setString(catalog.headers.map{$0+"\t"+(catalog.details[$0] ?? "")}.joined(separator:"\n"),forType:.string)}.disabled(catalog.details.isEmpty)}
                ScrollView{LazyVStack(alignment:.leading,spacing:6){ForEach(catalog.headers,id:\.self){key in if let value=catalog.details[key]{VStack(alignment:.leading,spacing:2){Text(key).font(.caption).foregroundStyle(.secondary);Text(value.isEmpty ? "—":value).font(.caption.monospaced()).textSelection(.enabled)};Divider()}}}}
                if !catalog.files.isEmpty{Menu("Associated XYZ / Psi4 / MOL2 files"){ForEach(catalog.files){file in Button(file.name+" · source"){catalog.openSource(file)}}}}
            }.padding(10).frame(minWidth:280,idealWidth:360)
        }
    }
    private func choose(root: Bool){
        pickingRoot=root
        if catalog.remote{picker=root ? .folder:.catalogCSV}
        else{let panel=NSOpenPanel();panel.canChooseDirectories=root;panel.canChooseFiles = !root;panel.message=root ? "Choose the dataset root":"Choose the BossTMC CSV";if panel.runModal() == .OK,let url=panel.url{if root{catalog.rootPath=url.path}else{catalog.csvPath=url.path}}}
    }
}
