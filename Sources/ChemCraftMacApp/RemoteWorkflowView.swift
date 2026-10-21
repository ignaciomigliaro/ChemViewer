import AppKit
import SwiftUI
import WebKit

struct RemoteWorkflowView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @ObservedObject private var remote = RemoteConnection.shared
    @ObservedObject private var runtime = RemoteWorkflowRuntime.shared
    @State private var picking: RemoteWorkflowPicker.Kind?
    @State private var confirmingRun = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(remote.profile.host.isEmpty ? "Choose an SSH connection" : remote.profile.host, systemImage: "server.rack").font(.headline)
                Spacer()
                Button("Open workflow…") { picking = .workflow }
                Button("New from structure…") { picking = .folder }.disabled(workspace.currentFrame?.atoms.isEmpty ?? true)
                Menu("More") {
                    Button("Upload local workflow inputs…") { remote.upload() }
                }
                if runtime.guiURL == nil { Button("Open remote editor") { runtime.open(config: remote.profile.config) } }
                else { Button("Close editor") { runtime.stop() } }
            }.padding(10).disabled(runtime.busy || remote.busy || remote.profile.host.isEmpty)
            if runtime.guiURL != nil {
                HStack {
                    Button("Save") { runtime.perform("save") }
                    Button("Check workflow") { runtime.perform("check") }
                    Button("Run on SLURM…") { confirmingRun = true }.buttonStyle(.borderedProminent)
                    Button("Resume") { runtime.perform("resume") }
                    Button("Refresh status") { runtime.perform("status") }
                    Toggle("Auto refresh", isOn: $remote.autoRefresh).toggleStyle(.checkbox)
                    Spacer()
                    if runtime.busy { ProgressView().controlSize(.small) }
                }.padding(.horizontal, 10).padding(.bottom, 6).disabled(runtime.busy || remote.busy)
            }
            Text(runtime.status).font(.caption).textSelection(.enabled).padding(.horizontal, 10).padding(.bottom, 8)
            Divider()
            if let url = runtime.guiURL { RemoteWorkflowWebView(url: url).id(url) }
            else {
                VStack(spacing: 14) {
                    Image(systemName: "server.rack").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Build and run on your SSH host").font(.title2)
                    Text("The editor browses cluster files and edits cluster templates. New workflows use SLURM. Set engine paths and review your cluster header before submitting.").multilineTextAlignment(.center).frame(maxWidth: 550)
                    if remote.profile.host.isEmpty { Button("Set up SSH…") { remote.presented = true } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !runtime.results.isEmpty {
                DisclosureGroup("Remote step results · Hartree") {
                    ScrollView([.horizontal,.vertical]) { Text(runtime.results).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 145)
                    Button("Copy results") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(runtime.results, forType: .string) }
                }.padding(8)
            }
        }
        .onChange(of: runtime.requestedPicker) { value in if let value { picking = value; runtime.requestedPicker = nil } }
        .onAppear { if let value = runtime.requestedPicker { picking = value; runtime.requestedPicker = nil } }
        .sheet(item: $picking) { kind in
            RemoteWorkflowPicker(kind: kind) { path in
                if kind == .folder { runtime.create(workspace: workspace, parent: path) }
                else { runtime.open(config: path) }
            }
        }
        .alert("Submit workflow on SLURM?", isPresented: $confirmingRun) {
            Button("Run on SLURM") { runtime.perform("run") }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Host: \(remote.profile.host)\nThe editor and template changes will be saved remotely, then checked before submission. Run can replace cached results; Resume continues an existing run.") }
        .task {
            if picking == nil && runtime.requestedPicker == nil && remote.isConnected && runtime.guiURL == nil && !runtime.busy { runtime.open(config: remote.profile.config) }
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
                if remote.autoRefresh && runtime.guiURL != nil && !runtime.busy && !remote.busy { runtime.perform("status") }
            }
        }
    }
}
private struct RemoteWorkflowWebView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> WKWebView { RemoteWorkflowRuntime.shared.webView(url) }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

/// Native SSH path picker; never invokes NSOpenPanel for remote operations.
struct RemoteWorkflowPicker: View {
    enum Kind: String, Identifiable { case folder, workflow, catalogCSV; var id: String { rawValue } }
    let kind: Kind
    var title: String? = nil
    var buttonTitle: String? = nil
    let choose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var remote = RemoteConnection.shared
    @ObservedObject private var runtime = RemoteWorkflowRuntime.shared
    @State private var directory = ""
    @State private var parent = "~"
    @State private var entries: [RemoteConnection.Entry] = []
    @State private var selected: String?
    @State private var loading = false
    @State private var error = ""
    @State private var requestID = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title ?? (kind == .folder ? "Create workflow in remote folder" : "Open remote workflow")).font(.headline)
            Text(remote.profile.host).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Home") { load("~") }; Button("Parent") { load(parent) }
                TextField("Remote folder", text: $directory).onSubmit { load(directory) }
                Button("Go") { load(directory) }
            }.disabled(loading)
            List(selection: $selected) {
                ForEach(entries.filter { $0.directory || ((kind == .workflow ? ["yaml","yml"] : kind == .catalogCSV ? ["csv"] : []).contains(URL(fileURLWithPath: $0.name).pathExtension.lowercased())) }) { entry in
                    Label(entry.name, systemImage: entry.directory ? "folder" : "doc.text").tag(entry.path)
                        .contentShape(Rectangle()).onTapGesture(count: 2) {
                            if entry.directory { load(entry.path) }
                            else if !runtime.busy { choose(entry.path); dismiss() }
                        }
                }
            }.disabled(loading)
            if loading { ProgressView().controlSize(.small) }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Text("Double-click folders to navigate.").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(buttonTitle ?? (kind == .folder ? "Create here" : "Open")) {
                    choose(kind == .folder ? directory : selected!); dismiss()
                }.keyboardShortcut(.defaultAction).disabled(loading || runtime.busy || !error.isEmpty || directory.isEmpty || (kind != .folder && !entries.contains { $0.path == selected && !$0.directory }))
            }
        }.padding(18).frame(minWidth: 640, minHeight: 450)
        .task { load(remote.explorerRoot.isEmpty ? remote.profile.directory : remote.explorerRoot) }
        .onDisappear { requestID = UUID() }
    }
    private func load(_ path: String) {
        let token = UUID(); requestID = token; let profile = remote.profile
        loading = true; error = ""; selected = nil
        Task {
            do {
                // Serialize with the shared explorer, rather than opening a new login/channel.
                while remote.busy { try await Task.sleep(nanoseconds: 50_000_000); guard requestID == token else { return } }
                guard requestID == token, profile.id == remote.profile.id else { return }
                remote.busy = true; defer { remote.busy = false }
                let result = try await remote.request(["action":"list", "path":path], profile: profile)
                guard requestID == token else { return }
                entries = try JSONDecoder().decode([RemoteConnection.Entry].self, from: JSONSerialization.data(withJSONObject: result["entries"] ?? []))
                directory = result["path"] as? String ?? path; parent = result["parent"] as? String ?? "~"; loading = false
            } catch { if requestID == token { loading = false; self.error = error.localizedDescription } }
        }
    }
}
