import AppKit
import ChemCraftCore
import WebKit

@MainActor
enum MechanismSmokeTest {
    private static var started = false

    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }
        started = true
        let draft = MechanismDraft.shared
        let catalog = BosTMCStore.shared
        let runtime = ChemistryRuntime.shared
        let args = CommandLine.arguments
        let evidence = args.firstIndex(of: "--render-evidence").map { URL(fileURLWithPath: args[$0 + 1]) }
        do {
            guard let evidence else { throw ParseError.malformed("Supply a native test evidence directory.") }
            func require(_ condition: Bool, _ message: String) throws {
                if !condition { throw ParseError.malformed(message) }
            }
            func pause() async { try? await Task.sleep(nanoseconds: 150_000_000) }
            func wait(_ description: String, until ready: () -> Bool) async throws {
                for _ in 0..<100 {
                    if ready() { return }
                    await pause()
                }
                throw ParseError.malformed(description)
            }
            func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
            func click(_ label: String, identifier: String? = nil) async throws {
                func button() -> NSButton? {
                    NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap(descendants)
                        .compactMap { $0 as? NSButton }.first { button in
                            (identifier.map { button.identifier?.rawValue == $0 } ?? (button.title == label)) && button.isEnabled
                        }
                }
                try await wait("Missing control \(label)", until: { button() != nil })
                button()?.performClick(nil)
                await pause()
            }

            let catalystXYZs = [
                "2\nSynthetic CuCl\nCu 0 0 0\nCl -2.1 0 0\n",
                "2\nSynthetic CuBr\nCu 0 0 0\nBr -2.3 0 0\n"
            ]
            let csv = evidence.appendingPathComponent("synthetic-catalog.csv")
            let rows = catalystXYZs.enumerated().map { index, xyz in
                "CANDIDATE_\(index + 1),Cu,0.0,1,\"\(xyz)\"\n"
            }
            try ("refcode,metal,charge,spinmult,xyz\n" + rows.joined()).write(to: csv, atomically: true, encoding: .utf8)
            workspace.activeTab = "ChemRefine"
            try await click("Reaction mechanism…")
            try await click("Choose from BOS-TMC…")
            catalog.remote = false
            catalog.filesRemote = false
            catalog.csvPath = csv.path
            catalog.cachePath = evidence.appendingPathComponent("index-cache").path
            catalog.rootPath = ""
            await pause()
            catalog.index()
            try await wait("Synthetic BOS-TMC index did not load: \(catalog.status)") { catalog.rows.count == 2 && !catalog.busy }
            for id in catalog.rows.map(\.id) {
                catalog.select(id)
                try await wait("BOS-TMC geometry unavailable") { !catalog.selecting && catalog.xyzURL != nil }
                try await click("Add previewed catalyst")
            }
            try await click("Add previewed catalyst")
            try require(draft.catalysts.count == 2, "Duplicate catalog entry changed the catalyst set")
            try require(Set(draft.catalysts.map(\.xyz)) == Set(catalystXYZs), "Catalyst XYZ bytes were changed")
            try require(draft.catalysts.allSatisfy { $0.charge == "0" && $0.multiplicity == 1 }, "BOS-TMC charge/spin metadata was lost")
            try await click("Back to mechanism")

            let substrates = try [0.28, 0.30].enumerated().map { index, x in
                try MechanismGeometry(name: "ammonia_\(index + 1)",
                    xyz: "4\nSynthetic NH3 variant\nN 0 0 0\nH \(x) 0.96 0\nH \(x) -0.48 0.831\nH \(x) -0.48 -0.831\n", charge: "0")
            }
            draft.stages[0].substrates = substrates
            try await click("Build in 3D…", identifier: "mechanism-build-initialCore")
            try require(draft.pending?.kind == .initialCore, "Wrong initial core builder route")
            let coreSource = "2\nInitial core\nN 2.1 0 0\nCu 0 0 0\n"
            workspace.loadPastedCoordinates(try XYZParser.parse(text: coreSource), source: coreSource)
            try await click("Capture whole structure")
            try require(workspace.activeTab == "ChemRefine" && draft.stages[0].initialCore?.anchor == 2,
                        "Initial core did not retain the one-based metal row")

            draft.pending = .init(stage: draft.stages[0].id, kind: .productCore)
            let productSource = "3\nProduct core with unrelated atom\nN 4.2 0 0\nCu 0 0 0\nAr 20 0 0\n"
            workspace.loadPastedCoordinates(try XYZParser.parse(text: productSource), source: productSource)
            workspace.selectedAtomIndices = [1, 0]
            let original = workspace.currentFrame
            try await click("Capture selected atoms")
            try require(workspace.currentFrame == original && workspace.selectedAtomIndices == [1, 0],
                        "Capturing a core modified the builder document")
            try require(draft.stages[0].productCore?.geometry.elements == ["N", "Cu"] && draft.stages[0].productCore?.anchor == 2,
                        "Selected core lost source order or picked an unselected atom")

            try await click("Add stage")
            try require(draft.stages.count == 2 && draft.stages[1].carry == draft.stages[0].id, "New stage lost predecessor")
            draft.stages[1].selector = .metal
            draft.stages[1].reagents = [substrates[0]]
            let rebound = try MechanismGeometry(name: "Rebind NH3", xyz: "2\nRebinding core\nN 2.05 0 0\nCu 0 0 0\n")
            try draft.add([rebound], to: .init(stage: draft.stages[1].id, kind: .productCore))
            await draft.loadSchema()
            try await wait("Installed ChemRefine engine schema unavailable") { draft.schema?.engines["pyscf"] != nil }
            draft.stages[1].expanded = false
            draft.stages[0].expanded = true
            draft.stages[0].section = .calculations
            try require(draft.stages[0].reactantSteps.isEmpty && draft.stages[0].productSteps.isEmpty
                        && draft.stages[0].tsSteps[0].method.isEmpty && draft.stages[0].scoringSteps[0].method.isEmpty,
                        "A fresh stage preselected endpoint chemistry or a method")
            for branch in [MechanismBranch.reactant, .product, .scoring, .ts] {
                draft.stages[0].calculationBranch = branch
                await pause()
                if branch == .reactant || branch == .product {
                    try await click("Add calculation", identifier: "mechanism-add-1-\(branch.rawValue)")
                }
                try await click("Add calculation", identifier: "mechanism-add-1-\(branch.rawValue)")
            }
            try require(draft.stages[0].reactantSteps.count == 2 && draft.stages[0].productSteps.count == 2
                        && draft.stages[0].scoringSteps.count == 2 && draft.stages[0].tsSteps.count == 2,
                        "Adding calculations did not target the intended branch")
            try require(draft.stages[0].reactantSteps[0].operation == nil,
                        "New preparation calculation chose an operation")
            draft.stages[0].reactantSteps[0].operation = "sp"
            do {
                _ = try await draft.previewYAML()
                throw ParseError.malformed("Blank ORCA method generated a template")
            } catch {
                try require(error.localizedDescription.contains("enter a method"), error.localizedDescription)
            }
            draft.stages[0].reactantSteps[0].method = "HF def2-SVP"
            draft.stages[0].productSteps[0].operation = "opt_sp"
            draft.stages[0].productSteps[0].method = "PBE def2-SVP"
            for index in draft.stages.indices {
                for step in draft.stages[index].scoringSteps.indices { draft.stages[index].scoringSteps[step].method = "HF def2-SVP" }
                for step in draft.stages[index].tsSteps.indices { draft.stages[index].tsSteps[step].method = "PBE def2-SVP" }
            }
            draft.stages[0].reactantSteps[1].engine = "pyscf"
            await pause()
            draft.stages[0].reactantSteps[1].operation = "sp"
            draft.stages[0].reactantSteps[1].method = "hf"
            draft.stages[0].reactantSteps[1].settingsYAML = "options:\n  basis: sto-3g"
            draft.stages[0].productSteps[1].operation = "freq"
            draft.stages[0].productSteps[1].method = "PBE def2-SVP"
            draft.stages[0].tsSteps[1].operation = "sp"
            draft.stages[0].guesserYAML = "timeout_seconds: 321"
            draft.mechanismYAML = "conformers: 5\nseed: 73"
            draft.workflowYAML = "template_dir: templates/custom"
            draft.cores = 4
            draft.workers = 2
            try require(draft.variantCount == 4, "Wrong Cartesian product count")
            draft.maxVariants = 3
            do {
                _ = try await draft.export(to: evidence)
                throw ParseError.malformed("Expected the composer to reject four combinations with a limit of three")
            } catch {
                try require(error.localizedDescription.contains("variant limit"), error.localizedDescription)
            }
            draft.maxVariants = 64

            let preview = try await draft.previewYAML()
            try require(preview.contains("engine: pyscf") && preview.contains("basis: sto-3g") && preview.contains("timeout_seconds: 321"),
                        "YAML preview omitted calculation or guesser settings")
            let url = try await draft.export(to: evidence)
            try url.path.write(to: evidence.appendingPathComponent("workflow-path.txt"), atomically: true, encoding: .utf8)
            draft.visible = false
            runtime.openLocalWorkflow(url, workspace: workspace)
            try await wait("Local ChemRefine web editor failed to start") { runtime.guiURL != nil }
            let browser = runtime.webView(for: runtime.guiURL!)
            var loaded: Int?
            for _ in 0..<100 {
                loaded = try? await browser.evaluateJavaScript("window.Alpine && Alpine.$data(document.body).cfg.mechanism?.stages?.length") as? Int
                if loaded == 2 { break }
                await pause()
            }
            try require(loaded == 2, "The real WebKit editor did not load both stages")
            let savedPath = try await runtime.saveWorkflowEditor(orcaPath: "")
            try require(savedPath == url.path || URL(fileURLWithPath: savedPath).resolvingSymlinksInPath() == url.resolvingSymlinksInPath(),
                        "Saving the form changed the workflow path")
            let roundTrip = try await browser.evaluateJavaScript("""
                (() => {
                  const stage = Alpine.$data(document.body).cfg.mechanism.stages[0];
                  const steps = stage.reactant.steps;
                  return steps.length === 2 && steps[1].engine === 'pyscf' &&
                    steps[1].options.method === 'hf' && steps[1].options.basis === 'sto-3g' &&
                    stage.product.steps[1].operation === 'freq' &&
                    stage.ts_guesser.scoring_steps.length === 2 &&
                    stage.ts_steps.length === 2;
                })()
                """) as? Bool
            try require(roundTrip == true, "The editor lost a method, engine, operation, or branch step")
            runtime.stopWorkflowTestServer()
            print("MECHANISM_PASS: native BOS-TMC selection, two catalysts and two substrates, core capture and anchor order, linked stages, limit validation, YAML export and real WebKit editor round trip.")
            fflush(stdout)
            exit(0)
        } catch {
            runtime.stopWorkflowTestServer()
            fputs("MECHANISM_FAIL: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
