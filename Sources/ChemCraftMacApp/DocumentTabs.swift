import AppKit
import Combine
import Foundation

struct RemoteFileOrigin {
    let profile: RemoteProfile
    let path: String
    var key: String { "ssh:" + profile.host + ":" + path }
}

@MainActor
final class DocumentTabs: ObservableObject {
    struct FileTab: Identifiable {
        let id: UUID
        let workspace: WorkspaceStore
        var url: URL?
        var origin: RemoteFileOrigin?
        @MainActor var title: String { workspace.document?.title ?? url?.lastPathComponent ?? "Untitled" }
        var key: String? { origin?.key ?? url?.standardizedFileURL.path }
    }
    @Published private(set) var files: [FileTab] = []
    @Published var pendingClose: UUID?
    @Published private(set) var activeID: UUID
    private var observations: [UUID: AnyCancellable] = [:]
    var activeWorkspace: WorkspaceStore { files.first(where: { $0.id == activeID })!.workspace }
    var activeFile: FileTab { files.first(where: { $0.id == activeID })! }
    init() {
        let workspace = WorkspaceStore(); activeID = workspace.documentIdentity
        files = [FileTab(id: workspace.documentIdentity, workspace: workspace)]; attach(workspace)
    }
    private func attach(_ workspace: WorkspaceStore) {
        workspace.documents = self
        observations[workspace.documentIdentity] = workspace.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    func activate(_ id: UUID) {
        guard id != activeID, let target = files.first(where: { $0.id == id }) else { return }
        activeWorkspace.suspendFileTasks(); activeID = id; target.workspace.resumeFileTasks()
    }
    @discardableResult func selectExisting(origin: RemoteFileOrigin) -> Bool {
        guard let existing = files.first(where: { $0.key == origin.key }) else { return false }
        activate(existing.id); return true
    }
    @discardableResult func open(_ url: URL, origin: RemoteFileOrigin? = nil, companions: [String:URL] = [:], reload: Bool = false) -> WorkspaceStore {
        let key = origin?.key ?? url.standardizedFileURL.path
        if let existing = files.first(where: { $0.key == key }) {
            activate(existing.id)
            if reload {
                guard !existing.workspace.hasUnsavedDocumentChanges else { existing.workspace.errorMessage = "Save your edits before refreshing this document."; return existing.workspace }
                existing.workspace.open(url, externalXYZFiles: companions)
            }
            return existing.workspace
        }
        let workspace: WorkspaceStore
        if activeFile.url == nil && activeWorkspace.document == nil && !activeWorkspace.isLoading { workspace = activeWorkspace }
        else {
            workspace = WorkspaceStore()
            workspace.renderingStyle = activeWorkspace.renderingStyle; workspace.showHydrogens = activeWorkspace.showHydrogens
            workspace.atomCaption = activeWorkspace.atomCaption; workspace.showDisplacementVectors = activeWorkspace.showDisplacementVectors
            attach(workspace); files.append(FileTab(id: workspace.documentIdentity, workspace: workspace))
            activate(workspace.documentIdentity)
        }
        if let index = files.firstIndex(where: { $0.id == workspace.documentIdentity }) { files[index].url = url; files[index].origin = origin }
        workspace.open(url, externalXYZFiles: companions)
        return workspace
    }
    func newMolecule() {
        if activeWorkspace.document != nil || activeWorkspace.isLoading {
            let workspace = WorkspaceStore(); attach(workspace)
            files.append(FileTab(id: workspace.documentIdentity, workspace: workspace)); activate(workspace.documentIdentity)
        }
        activeWorkspace.newMolecule(); activeWorkspace.presentFragmentLibrary()
    }
    func requestCloseActive() { if !close(activeID) { pendingClose = activeID } }
    @discardableResult func close(_ id: UUID, discard: Bool = false) -> Bool {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return true }
        let workspace = files[index].workspace
        guard discard || !workspace.hasUnsavedDocumentChanges else { return false }
        workspace.suspendFileTasks(); workspace.disposeClosedDocument()
        if files.count == 1 {
            let blank = WorkspaceStore(); attach(blank); files.append(FileTab(id: blank.documentIdentity, workspace: blank)); activeID = blank.documentIdentity
        } else if activeID == id {
            activeID = files[index == files.count - 1 ? index - 1 : index + 1].id
            activeWorkspace.resumeFileTasks()
        }
        files.removeAll { $0.id == id }; observations.removeValue(forKey: id)
        return true
    }
}
