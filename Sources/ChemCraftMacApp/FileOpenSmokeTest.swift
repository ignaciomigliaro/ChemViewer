import AppKit
import ChemCraftCore

@MainActor
enum FileOpenSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        do {
            func require(_ value: Bool, _ message: String) throws { if !value { throw ParseError.malformed(message) } }
            // This workflow deliberately closes its window: refuse production bundles
            // or any ambiguous Launch Services session before opening any test input.
            guard let bundleID = Bundle.main.bundleIdentifier, bundleID.hasPrefix("org.cleanroom.ChemViewer.FileOpenTest."),
                  NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count == 1,
                  NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier == ProcessInfo.processInfo.processIdentifier else {
                throw ParseError.malformed("File-open acceptance requires one uniquely identified isolated test bundle")
            }
            guard let tabs = workspace.documents else { throw ParseError.noGeometry }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ChemViewer-open-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let urls = (0..<4).map { folder.appendingPathComponent("molecule \($0).xyz") }
            for (i,url) in urls.enumerated() { try "2\nsynthetic external open \(i)\nH 0 0 0\nH 0 0 0.74\n".write(to: url, atomically: true, encoding: .utf8) }
            func windows() -> [NSWindow] { NSApp.windows.filter { $0.isVisible && $0.title.hasPrefix("ChemViewer ") && $0.sheetParent == nil } }
            func open(_ files: [URL]) throws {
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                process.arguments = ["-a", Bundle.main.bundlePath] + files.map(\.path)
                try process.run(); process.waitUntilExit()
                try require(process.terminationStatus == 0, "Launch Services file-open request failed")
            }
            func settle(_ count: Int) async throws {
                for _ in 0..<100 {
                    if tabs.files.count == count && tabs.files.allSatisfy({ !$0.workspace.isLoading && $0.workspace.document != nil }) && windows().count == 1 { break }
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
                try require(tabs.files.count == count, "External opens produced \(tabs.files.count) tabs instead of \(count)")
                try require(windows().count == 1, "External open produced duplicate/no main windows: \(windows().count)")
                try require(tabs.files.allSatisfy { $0.workspace.errorMessage == nil && $0.workspace.document != nil }, "External document load failed")
            }
            try open([urls[0]]); try await settle(1)
            let first = tabs.activeWorkspace
            first.selectedAtomIndices = [0]
            first.replaceCurrentAtoms([Atom(id: 0, element: "He", position: .zero), Atom(id: 1, element: "H", position: Vector3(0,0,0.74))])
            let edited = first.currentFrame
            try open([urls[1], urls[2]]); try await settle(3)
            try open([urls[0], urls[1]]); try await settle(3)
            try require(first.currentFrame == edited && first.hasUnsavedDocumentChanges, "Repeated Finder open lost unsaved edits")
            // Close only the test's own window, then reopen another file into the same tabs.
            guard let window = windows().first, window === NSApp.mainWindow || window === NSApp.keyWindow else { throw ParseError.malformed("Refuse closing a window not owned by the isolated test application") }
            window.close()
            try await Task.sleep(nanoseconds: 200_000_000)
            try open([urls[3]]); try await settle(4)
            try require(first.currentFrame == edited, "Reopening main window discarded retained tabs")
            // Launch-time events can precede view configuration.
            let queued = FileOpenApplicationDelegate(), coldTabs = DocumentTabs()
            queued.application(NSApp, open: [urls[0],urls[1],urls[0]])
            queued.configure(documents: coldTabs, showWindow: {})
            try require(coldTabs.files.count == 2, "Startup queue lost or duplicated files")
            for tab in coldTabs.files { tab.workspace.cancelDocumentLoad() }
            print("FILE_OPEN_PASS: real Launch Services single/batch/repeated file events; one main window; existing tabs and unsaved edits retained; closed-window reopen; startup queue deduplicated.")
            fflush(stdout); exit(0)
        } catch { fputs("FILE_OPEN_FAIL: \(error.localizedDescription)\n", stderr); exit(1) }
    }
}
