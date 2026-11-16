import AppKit
import ChemCraftCore

@MainActor enum PasteCoordinatesSmokeTest {
    private static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        do {
            func trace(_ text: String) { fputs("PASTE_STAGE: \(text)\n", stderr) }
            trace("started")
            func require(_ condition: Bool, _ message: String) throws { if !condition { throw ParseError.malformed(message) } }
            func pause() async { try? await Task.sleep(nanoseconds: 400_000_000) }
            guard let tabs = workspace.documents else { throw ParseError.noGeometry }
            trace("tabs ready")
            workspace.loadPastedCoordinates(try PastedCoordinates.parse("He 0 0 0"), source: "He 0 0 0")
            workspace.replaceCurrentAtoms([Atom(id: 0, element: "He", position: Vector3(4,5,6))])
            try require(workspace.canUndoGeometry && workspace.hasUnsavedDocumentChanges, "Original edit setup failed")
            let original = workspace.currentFrame, id = workspace.documentIdentity, count = tabs.files.count
            trace("original ready")
            workspace.isPasteCoordinatesPresented = true
            await pause()
            trace("sheet requested")
            guard let sheet = NSApp.windows.first(where: { $0.sheetParent != nil }), let root = sheet.contentView else { throw ParseError.malformed("Paste sheet missing") }
            func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
            for _ in 0..<15 {
                if descendants(root).contains(where: { $0 is NSTextView }) { break }
                await pause()
            }
            guard let editor = descendants(root).compactMap({ $0 as? NSTextView }).first,
                  let render = descendants(root).compactMap({ $0 as? NSButton }).first(where: { $0.identifier?.rawValue == "render-pasted-coordinates" || $0.title == "Render" }) else { throw ParseError.malformed("Paste controls missing") }
            func enter(_ text: String) async {
                sheet.makeFirstResponder(editor)
                editor.string = text
                editor.didChangeText()
                await pause()
            }
            trace("controls found")
            await enter("H nan 0 0")
            render.performClick(nil); await pause()
            try require(tabs.files.count == count && workspace.currentFrame == original && sheet.sheetParent != nil, "Invalid paste changed document or dismissed sheet")
            trace("invalid refused")
            let source = "O 0 0 0\nH 0.75 0.5 -0.25\nH -0.75 0.5 -0.25\n"
            await enter(source)
            render.performClick(nil); await pause(); await pause()
            trace("render invoked")
            let pasted = tabs.activeWorkspace
            try require(tabs.files.count == count + 1 && tabs.activeID != id, "Paste did not open a separate tab")
            try require(workspace.currentFrame == original && workspace.hasUnsavedDocumentChanges && workspace.canUndoGeometry, "Paste discarded original edits")
            try require(pasted.hasUnsavedDocumentChanges && pasted.sourceText == source && pasted.activeTab == "Image", "Pasted source/dirty state missing")
            try require(pasted.currentFrame?.atoms.map(\.position) == [Vector3(0,0,0), Vector3(0.75,0.5,-0.25), Vector3(-0.75,0.5,-0.25)], "Cartesian oracle mismatch")
            guard let view = AnimationExporter.viewport() else { throw ParseError.noGeometry }
            try require(view.projectedAtomPoint(2) != nil, "Pasted molecule not projected")
            let args = CommandLine.arguments
            let folder = args.firstIndex(of: "--render-evidence").map { URL(fileURLWithPath: args[$0 + 1]) } ?? FileManager.default.temporaryDirectory
            let image = folder.appendingPathComponent("paste.png")
            view.capture(to: image)
            for _ in 0..<60 { if FileManager.default.fileExists(atPath: image.path) { break }; await pause() }
            try require(NSImage(contentsOf: image) != nil, "Pasted Metal image missing")
            tabs.activate(id); await pause()
            try require(workspace.currentFrame == original, "Original document lost after switching back")
            print("PASTE_COORDINATES_PASS: native text editor and Render button, malformed refusal, separate dirty tab, preserved original edits/source, exact Cartesian oracle, live Metal projection/PNG.")
            fflush(stdout); exit(0)
        } catch { fputs("PASTE_COORDINATES_FAIL: \(error)\n", stderr); exit(1) }
    }
}
