import AppKit
import SwiftUI

struct DocumentTabStrip: View {
    @ObservedObject var documents: DocumentTabs
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(documents.files) { tab in
                    HStack(spacing: 7) {
                        Button { documents.activate(tab.id) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tab.origin == nil ? "doc.text" : "network")
                                Text(tab.title).lineLimit(1)
                                if tab.workspace.hasUnsavedDocumentChanges { Circle().fill(Color.accentColor).frame(width: 6, height: 6) }
                                if tab.workspace.isLoading { ProgressView().controlSize(.mini) }
                            }.frame(minWidth: 100, maxWidth: 225, alignment: .leading)
                        }.buttonStyle(.plain)
                        Button { if !documents.close(tab.id) { documents.pendingClose = tab.id } } label: { Image(systemName: "xmark").font(.caption) }
                            .buttonStyle(.plain).help("Close \(tab.title)").accessibilityLabel("Close \(tab.title)")
                    }.padding(.horizontal, 10).padding(.vertical, 8)
                    .background(tab.id == documents.activeID ? Color.white : Color(nsColor: .controlBackgroundColor))
                    .overlay(alignment: .bottom) { if tab.id == documents.activeID { Rectangle().fill(Color.accentColor).frame(height: 2) } }
                    .id(tab.id)
                    .help(tab.origin.map { $0.profile.host + ":" + $0.path } ?? tab.url?.path ?? tab.title)
                    Divider().frame(height: 32)
                }
            }
        }.onChange(of: documents.activeID) { proxy.scrollTo($0, anchor: .center) }
        }.frame(height: 35).background(Color(nsColor: .windowBackgroundColor))
        .alert("Close document with unsaved changes?", isPresented: Binding(get: { documents.pendingClose != nil }, set: { if !$0 { documents.pendingClose = nil } })) {
            Button("Discard changes", role: .destructive) { if let id = documents.pendingClose { _ = documents.close(id, discard: true) }; documents.pendingClose = nil }
            Button("Cancel", role: .cancel) { documents.pendingClose = nil }
        } message: { Text("\(documents.files.first(where: { $0.id == documents.pendingClose })?.title ?? "Document") has geometry or drawing edits. Cancel to save the project/drawing before closing.") }
    }
}

struct RemoteExplorerView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject var remote = RemoteConnection.shared
    @State private var directory = ""
    @State private var allFiles = true
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("REMOTE FILES", systemImage: "network").font(.caption.bold())
                Spacer()
                Button { remote.presented = true } label: { Image(systemName: "gearshape") }.help("SSH connection settings")
                Button { remote.loadExplorerFolder(remote.explorerRoot.isEmpty ? remote.profile.directory : remote.explorerRoot, makeRoot: true, refresh: true) } label: { Image(systemName: "arrow.clockwise") }.help("Refresh remote explorer")
                Button { remote.explorerVisible = false } label: { Image(systemName: "sidebar.left") }.help("Hide remote explorer")
            }.buttonStyle(.plain)
            Text(remote.profile.host.isEmpty ? "Choose a connection in Settings" : remote.profile.host).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { remote.loadExplorerFolder("~", makeRoot: true) } label: { Image(systemName: "house") }.help("Remote home folder").disabled(remote.busy)
                Button { remote.loadExplorerFolder(URL(fileURLWithPath: remote.explorerRoot).deletingLastPathComponent().path, makeRoot: true) } label: { Image(systemName: "arrow.up") }.help("Parent folder").disabled(remote.busy || remote.explorerRoot.isEmpty || remote.explorerRoot == "/")
                TextField("Remote folder", text: $directory).font(.caption).onSubmit { remote.loadExplorerFolder(directory, makeRoot: true) }
                Button("Go") { remote.loadExplorerFolder(directory, makeRoot: true) }.disabled(remote.busy)
            }
            HStack {
                Toggle("Show all files", isOn: $allFiles).font(.caption).toggleStyle(.checkbox)
                Spacer(minLength: 2)
                Picker("Sort", selection: $remote.explorerOrder) {
                    ForEach(RemoteConnection.ExplorerOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().font(.caption).frame(width: 98).help("Sort files by name or extension; folders stay first")
            }
            if remote.explorerRoot.isEmpty || remote.explorerNodes[remote.explorerRoot] == nil {
                Text(remote.busy ? "Loading remote folder…" : "Folder has not loaded. Browse to connect or retry.").font(.caption).foregroundStyle(.secondary)
                Button("Browse saved connection") { remote.loadExplorerFolder(remote.profile.directory, makeRoot: true) }.disabled(remote.busy || remote.profile.host.isEmpty)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(remote.sortedExplorerEntries(remote.explorerRoot)) { entry in
                            RemoteExplorerRow(entry: entry, allFiles: allFiles, remote: remote)
                        }
                        if let entries = remote.explorerNodes[remote.explorerRoot] {
                            if entries.isEmpty { Text("This folder is empty.").font(.caption).foregroundStyle(.secondary) }
                            else if !allFiles && !entries.contains(where: { $0.directory || $0.isMolecularFile }) {
                                Text("No molecular files here. Enable Show all files or go to the parent folder.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 100, maxHeight: .infinity)
            }
            if remote.busy { ProgressView().controlSize(.mini) }
            Text(remote.connectionStatus).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            Text(remote.status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2).help(remote.status)
        }.padding(9).frame(minWidth: 230, minHeight: 175)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            directory = remote.explorerRoot.isEmpty ? remote.profile.directory : remote.explorerRoot
        }
        .task(id: remote.explorerIdentity) { await remote.ensureExplorerLoaded() }
        .onChange(of: remote.explorerRoot) { directory = $0.isEmpty ? remote.profile.directory : $0 }
    }
}

private struct RemoteExplorerRow: View {
    let entry: RemoteConnection.Entry
    let allFiles: Bool
    @ObservedObject var remote: RemoteConnection
    @EnvironmentObject private var workspace: WorkspaceStore
    private var supported: Bool { entry.isMolecularFile }
    var body: some View {
        if entry.directory {
            DisclosureGroup(isExpanded: Binding(get: { remote.expandedExplorerPaths.contains(entry.path) }, set: { expanded in remote.toggleExplorerFolder(entry.path, expanded: expanded) })) {
                if let children = remote.explorerNodes[entry.path] {
                    ForEach(remote.sortedExplorerEntries(entry.path)) { child in RemoteExplorerRow(entry: child, allFiles: allFiles, remote: remote) }
                    if children.isEmpty { Text("Empty folder").font(.caption).foregroundStyle(.secondary) }
                } else { Text(remote.busy ? "Loading…" : "Expand again to retry").font(.caption).foregroundStyle(.secondary) }
            } label: {
                Label(entry.name, systemImage: "folder").lineLimit(1).font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    .onTapGesture(count: 2) { remote.enterExplorerFolder(entry.path) }
                    .accessibilityIdentifier("remote-folder:" + entry.path)
                    .help("Double-click to enter this folder; use the arrow to expand it")
                    .contextMenu { Button("Use as explorer root") { remote.loadExplorerFolder(entry.path, makeRoot: true) } }
            }
        } else if allFiles || supported {
            Button {
                if supported {
                    let origin = RemoteFileOrigin(profile: remote.profile, path: entry.path)
                    if workspace.documents?.selectExisting(origin: origin) != true { remote.perform("read", path: entry.path, workspace: workspace) }
                } else { remote.perform("edit", path: entry.path); remote.presented = true }
            } label: {
                Label(entry.name, systemImage: entry.name.hasSuffix(".xyz") ? "atom" : "doc.text")
                    .font(.system(size: 12)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 3)
            }.buttonStyle(.plain).disabled(remote.busy)
            .help(entry.path)
            .contextMenu {
                if supported { Button("Open in document tab") { remote.perform("read", path: entry.path, workspace: workspace) } }
                Button("Edit remote text…") { remote.perform("edit", path: entry.path); remote.presented = true }
                if entry.name.hasSuffix(".yaml") || entry.name.hasSuffix(".yml") {
                    Button("Use ChemRefine workflow") { remote.profile.config = entry.path; remote.saveProfile(); remote.workflowRemoteSelected = true; workspace.activeTab = "ChemRefine"; RemoteWorkflowRuntime.shared.open(config: entry.path) }
                }
            }
        }
    }
}
