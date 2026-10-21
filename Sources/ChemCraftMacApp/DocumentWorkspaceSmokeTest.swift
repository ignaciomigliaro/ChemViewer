import AppKit
import ChemCraftCore
import Foundation

@MainActor
enum DocumentWorkspaceSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        func require(_ value: Bool, _ message: String) throws { if !value { throw ParseError.malformed(message) } }
        func wait(_ store: WorkspaceStore) async throws {
            for _ in 0..<200 { if !store.isLoading { break }; try await Task.sleep(nanoseconds: 30_000_000) }
            try require(!store.isLoading && store.errorMessage == nil && store.document != nil, "Document load failed: \(store.errorMessage ?? "timeout")")
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        func views(_ view: NSView) -> [MolecularMTKView] {
            (view as? MolecularMTKView).map { [$0] } ?? view.subviews.flatMap(views)
        }
        func viewport() throws -> MolecularMTKView {
            guard let view = NSApp.windows.filter({ $0.isVisible && $0.sheetParent == nil }).compactMap(\.contentView).flatMap(views).first else { throw ParseError.malformed("No active molecular renderer") }; return view
        }
        do {
            guard let tabs = workspace.documents else { throw ParseError.malformed("Document tabs were not installed") }
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/chemviewer-document-evidence")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let aURL = folder.appendingPathComponent("hydrogen.xyz")
            try "2\nindependent frame 1\nH 0 0 0\nH 0 0 .74\n2\nindependent frame 2\nH 0 0 0\nH 0 0 .80\n".write(to: aURL, atomically: true, encoding: .utf8)
            let bURL = folder.appendingPathComponent("water.inp")
            try "! HF STO-3G\n* xyz -1 2\nO 0 0 0\nH .9572 0 0\nH -.239  .9266 0\n*\n".write(to: bURL, atomically: true, encoding: .utf8)
            let a = tabs.open(aURL); try await wait(a)
            a.selectedAtomIndices = [0,1]; a.setSelectionMeasurementVisible(true)
            NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "left")
            NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "in")
            try await Task.sleep(nanoseconds: 80_000_000)
            let aView = try viewport(); let cameraA = aView.captureViewportState()
            var positioned = cameraA; positioned.labelOffsets["test-distance"] = CGPoint(x: 30, y: -20); aView.restoreViewportState(positioned)
            a.toggleTrajectoryPlayback()
            let b = tabs.open(bURL); try await wait(b)
            try require(a !== b && b.charge == -1 && b.multiplicity == 2, "Inputs shared state or lost charge/spin")
            let frozenFrame = a.frameIndex
            let frozenDrawCount = aView.completedFrameCount
            try await Task.sleep(nanoseconds: 450_000_000)
            try require(!a.isPlayingTrajectory && !a.isVibrating && a.frameIndex == frozenFrame, "Inactive tab kept animating")
            try require(aView.isPaused && !aView.renderingReady && aView.scene.atoms.isEmpty && aView.completedFrameCount == frozenDrawCount, "Dismantled renderer kept drawing")
            let shared = try viewport(); let builds = shared.meshBuildCount
            let bAtoms = b.currentFrame!.atoms
            b.selectedAtomIndices = [2]
            NotificationCenter.default.post(name: .init("ChemViewerViewportAction"), object: "right")
            let cameraB = shared.captureViewportState()
            tabs.activate(a.documentIdentity); try await Task.sleep(nanoseconds: 140_000_000)
            a.stopTrajectoryPlayback()
            let returned = try viewport()
            try require(returned === shared, "Loaded tab switch allocated another renderer")
            try require(returned.captureViewportState().yaw == cameraA.yaw && returned.captureViewportState().zoom == cameraA.zoom, "Tab switch lost the viewing angle/zoom")
            try require(returned.captureViewportState().labelOffsets["test-distance"] == CGPoint(x:30,y:-20), "Label placements were not restored")
            try require(a.selectedAtomIndices == [0,1] && !a.pinnedMeasurementSelections.isEmpty, "Tab switch lost selection/measurements")
            for _ in 0..<25 {
                tabs.activate(b.documentIdentity); try await Task.sleep(nanoseconds: 20_000_000)
                tabs.activate(a.documentIdentity); try await Task.sleep(nanoseconds: 20_000_000)
            }
            try require(try viewport() === shared && shared.meshBuildCount == builds, "Repeated switches rebuilt GPU meshes or leaked renderers")
            tabs.activate(b.documentIdentity); try await Task.sleep(nanoseconds: 100_000_000)
            try require(b.selectedAtomIndices == [2] && shared.captureViewportState().yaw == cameraB.yaw, "Second document state changed")
            b.activeTab = "Abstract"; try await Task.sleep(nanoseconds: 150_000_000)
            try require(try viewport().captureViewportState().yaw == cameraB.yaw, "Abstract lost the document camera")
            tabs.activate(a.documentIdentity); try await Task.sleep(nanoseconds: 100_000_000)
            tabs.activate(b.documentIdentity); try await Task.sleep(nanoseconds: 100_000_000)
            try require(b.activeTab == "Abstract" && (try viewport()).captureViewportState().yaw == cameraB.yaw, "Abstract state crossed file tabs")
            b.activeTab = "Image"; try await Task.sleep(nanoseconds: 100_000_000)
            let count = tabs.files.count
            _ = tabs.open(bURL); try require(tabs.files.count == count, "Opening an existing file duplicated its tab")
            tabs.activate(a.documentIdentity); try await Task.sleep(nanoseconds: 80_000_000)
            var edited = a.currentFrame!.atoms; edited[1].position.z = 1.2; a.replaceCurrentAtoms(edited)
            try require(a.hasUnsavedDocumentChanges && a.canUndoGeometry && b.currentFrame!.atoms == bAtoms, "Geometry edit leaked into another document")
            try require(!tabs.close(a.documentIdentity) && tabs.files.count == count, "Unsaved geometry was silently discarded")
            a.undoGeometry(); try require(b.currentFrame!.atoms == bAtoms, "Undo history crossed documents")
            let template = folder.appendingPathComponent("template.inp")
            try "! XTB2 Opt\n".write(to: template, atomically: true, encoding: .utf8)
            let input = tabs.open(template); try await wait(input)
            try require(input.activeTab == "Source" && input.document!.frames.isEmpty && input.sourceText == "! XTB2 Opt\n", "Coordinate-free template did not open as original Source")
            _ = tabs.close(input.documentIdentity)
            tabs.activate(b.documentIdentity)
            let origin = RemoteFileOrigin(profile: RemoteProfile(host:"synthetic-remote"), path:"/synthetic/hydrogen.xyz")
            let remoteTab = tabs.open(aURL, origin: origin); try await wait(remoteTab)
            let remoteCount = tabs.files.count
            _ = tabs.open(aURL, origin: origin); try require(tabs.files.count == remoteCount && tabs.selectExisting(origin: origin), "Remote file tabs were duplicated")
            _ = tabs.close(remoteTab.documentIdentity)
            // File-local drawing state is retained while its automatic worker is canceled.
            a.drawing.autoPreview = false
            var sketch = MolecularSketch(); _ = try sketch.addAtom("C", x:0, y:0); a.drawing.commit(sketch)
            tabs.activate(a.documentIdentity); tabs.activate(b.documentIdentity)
            try require(!a.drawing.busy && a.drawing.graph.atoms.count == 1 && b.drawing.graph.atoms.isEmpty, "Drawing state or background worker leaked across tabs")
            _ = tabs.close(a.documentIdentity, discard: true)
            let tempURL = folder.appendingPathComponent("closable.xyz"); try "1\nfixture\nHe 0 0 0\n".write(to: tempURL, atomically: true, encoding: .utf8)
            var temporary: WorkspaceStore? = tabs.open(tempURL); try await wait(temporary!)
            let closingID = temporary!.documentIdentity; weak var closed = temporary; temporary = nil
            let closeEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: NSApp.keyWindow?.windowNumber ?? 0, context: nil, characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
            let handled = NSApp.mainMenu?.performKeyEquivalent(with: closeEvent) ?? false
            try require(handled && !tabs.files.contains(where: { $0.id == closingID }), "Cmd-W did not close the active document tab")
            tabs.activate(b.documentIdentity)
            try await Task.sleep(nanoseconds: 250_000_000)
            try require(closed == nil || (closed?.document == nil && closed?.sourceText.isEmpty == true && closed?.canUndoGeometry == false), "Closed tab retained parsed geometry, source or undo data")
            try require(NSApp.windows.filter({ $0.isVisible && $0.sheetParent == nil }).compactMap(\.contentView).flatMap(views).count == 1, "Background documents retained visible Metal viewers")
            try require(try viewport().renderingReady, "Active renderer was not restored after source/drawing views")
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.sheetParent == nil }), let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]), let png = NSBitmapImageRep(cgImage:image).representation(using:.png, properties:[:]) { try png.write(to:folder.appendingPathComponent("document-tabs.png")) }
            print("DOCUMENT_WORKSPACE_PASS: ORCA input/XYZ tabs, 50 loaded switches with one shared renderer/mesh, camera/zoom/label/selection preservation, inactive timers paused, independent edits/undo/drawings, dirty-close refusal, remote dedup, template Source, Abstract view restoration, and closed-document data cleanup.")
            fflush(stdout); exit(0)
        } catch { print("DOCUMENT_WORKSPACE_FAIL: \(error)"); fflush(stdout); exit(1) }
    }
}
