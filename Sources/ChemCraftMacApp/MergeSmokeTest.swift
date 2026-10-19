import AppKit
import ChemCraftCore

@MainActor enum MergeSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        do {
            func check(_ value: Bool, _ text: String) throws { if !value { throw AnimationExportError.message(text) } }
            func pause() async throws { try await Task.sleep(nanoseconds: 250_000_000) }
            try await pause()
            workspace.newMolecule()
            workspace.addBuildingFragment(BuildingProject.fragment(1))
            try check(workspace.currentFrame?.atoms.count == 5, "Methane creation failed")
            let methane = workspace.currentFrame!.atoms
            workspace.selectedAtomIndices = [1]
            workspace.attachBuildingFragment(BuildingProject.fragment(3), leaving: 1)
            try check(workspace.currentFrame?.atoms.count == 8, "Ethane attachment failed")
            try check(workspace.selectedAtomIndices == [4, 5, 6, 7], "Attached fragment selection failed")
            workspace.undoGeometry()
            try check(workspace.currentFrame?.atoms == methane && workspace.selectedAtomIndices == [1], "Attachment undo failed")
            workspace.redoGeometry()
            try check(workspace.currentFrame?.atoms.count == 8, "Attachment redo failed")
            workspace.selectImportedGroup()
            try check(workspace.selectedAtomIndices == [4, 5, 6, 7], "Fragment groups not restored by redo")
            workspace.duplicateSelectedAtoms()
            try check(workspace.currentFrame?.atoms.count == 12, "Duplication failed")
            workspace.deleteSelectedAtoms()
            try check(workspace.currentFrame?.atoms.count == 8, "Deletion failed")
            workspace.undoGeometry(); workspace.redoGeometry()
            try check(workspace.currentFrame?.atoms.count == 8, "Topology redo failed")
            workspace.selectBuilderIndices("1,5")
            workspace.setBuildingBondAxis()
            workspace.selectBuilderIndices("5-8")
            let before = workspace.currentFrame!.atoms
            workspace.transformBuildingSelection(axis: "Bond", distance: 0, degrees: 30)
            let after = workspace.currentFrame!.atoms
            try check(workspace.errorMessage == nil, workspace.errorMessage ?? "Bond axis")
            try check(Array(before.prefix(4)) == Array(after.prefix(4)), "Bond transform moved outside atoms")
            try check(before[5].position != after[5].position, "Bond rotation did not move fragment")
            workspace.undoGeometry()
            workspace.editElement("N", insert: false)
            try check(workspace.currentFrame!.atoms[4].element == "N", "Element replacement failed")
            workspace.undoGeometry()
            workspace.editElement("O", insert: true)
            try check(workspace.currentFrame!.atoms.count == 9, "Atom insertion failed")
            workspace.undoGeometry()
            workspace.charge = -1; workspace.multiplicity = 2
            let project = try workspace.buildingProject()
            try check(try project.orcaGeometryText().contains("* xyz -1 2"), "ORCA geometry metadata failed")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ChemViewer-merge-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("legacy.mvproject")
            try JSONEncoder().encode(project).write(to: url)
            workspace.open(url)
            for _ in 0..<200 { if !workspace.isLoading { break }; try await Task.sleep(nanoseconds: 25_000_000) }
            try await pause()
            try check(workspace.errorMessage == nil && workspace.currentFrame?.atoms == project.atoms && workspace.currentGroups == project.groups && workspace.selectedAtomIndices == project.selection && workspace.charge == -1 && workspace.multiplicity == 2, "Legacy project reopen failed")
            workspace.atomCaption = .elementNumbers; workspace.showHydrogens = false
            workspace.isBuilderVisible = true
            try await pause()
            guard let view = AnimationExporter.viewport() else { throw AnimationExportError.message("Merged Metal view missing") }
            view.draw(); try await pause()
            try check(view.renderingReady && view.scene.style == .paton, "Paton renderer not retained")
            try check(view.scene.showHydrogens == false && view.scene.atomCaption == .elementNumbers && !view.measurementOverlay.captions.isEmpty, "Captions or H visibility not connected")
            try check(view.measurementOverlay.captions.count == project.atoms.filter { $0.element != "H" }.count, "Hidden H captions visible")
            workspace.showHydrogens = true; workspace.atomCaption = .none
            let evidence = URL(fileURLWithPath: "/Users/nacho/Downloads/chemviewer-merge-work")
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
            if let window = view.window {
                window.setContentSize(NSSize(width: 1280, height: 850)); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
                try await pause()
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-l", String(window.windowNumber), evidence.appendingPathComponent("merged-window.png").path]
                try process.run(); process.waitUntilExit()
                view.capture(to: evidence.appendingPathComponent("merged-molecule.png"))
                try await pause()
                if let content = window.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                    content.cacheDisplay(in: content.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])?.write(to: evidence.appendingPathComponent("merged-layout-offscreen.png"))
                }
            }
            for tab in ["Abstract", "Source", "Coord", "Image/Abs", "Image"] { workspace.activeTab = tab; try await pause() }
            print("MERGE_SMOKE_PASS: classic GUI + native Paton, fragment add/attach/groups, atom insert/replace/duplicate/delete, topology undo/redo, saved legacy projects, ORCA charge/multiplicity, bond-axis rotation, captions/H visibility, five tabs")
            exit(0)
        } catch { fputs("MERGE_SMOKE_FAIL: \(error)\n", stderr); exit(1) }
    }
}
