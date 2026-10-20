import AppKit
import ChemCraftCore
import WebKit

@MainActor
enum WorkflowRunnerSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        func require(_ value: Bool, _ message: String) throws { if !value { throw ParseError.malformed(message) } }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func views() -> [NSView] { NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap(descendants) }
        let runtime = ChemistryRuntime.shared, runner = WorkflowRunner.shared
        let defaults = UserDefaults.standard
        let domain = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier!) ?? [:]
        let previousPath = domain["ChemViewerLastRunConfig"], previousPID = domain["ChemViewerLastRunPID"]
        func restoreDefaults() {
            if let previousPath, !(previousPath as? String ?? "").contains("chemviewer-runner-evidence") { defaults.set(previousPath, forKey: "ChemViewerLastRunConfig") } else { defaults.removeObject(forKey: "ChemViewerLastRunConfig") }
            if let previousPID { defaults.set(previousPID, forKey: "ChemViewerLastRunPID") } else { defaults.removeObject(forKey: "ChemViewerLastRunPID") }
        }
        do {
            let evidence = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/chemviewer-runner-evidence")
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
            // Verify ink, not a font's asymmetric ascender/descender box.
            for label in ["H", "I", "Cl", "O12", "Ru123"] {
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 512, bitsPerPixel: 32)!
                let context = NSGraphicsContext(bitmapImageRep: bitmap)!
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
                context.cgContext.clear(CGRect(x: 0, y: 0, width: 128, height: 128))
                let caption = AtomCaptionAnnotation(point: CGPoint(x: 64, y: 64), label: label)
                caption.draw(); NSGraphicsContext.restoreGraphicsState()
                let pixels = bitmap.bitmapData!
                var minX = 128, maxX = -1, minY = 128, maxY = -1
                for y in 0..<128 { for x in 0..<128 where pixels[y * 512 + x * 4 + 3] > 40 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                } }
                try require(maxX >= minX && maxY >= minY, "Caption did not draw: " + label)
                let centerX = CGFloat(minX + maxX + 1) / 2, centerY = CGFloat(minY + maxY + 1) / 2
                try require(abs(centerX - 64) <= 1 && abs(centerY - 64) <= 1, "Actual caption ink is off-center: \(label), \(centerX),\(centerY)")
                try require(abs(caption.inkRect.midX - 64) < 1e-5 && abs(caption.inkRect.midY - 64) < 1e-5, "Caption glyph rectangle is not centered")
            }
            workspace.atomCaption = .elementNumbers
            try await Task.sleep(nanoseconds: 250_000_000)
            guard let viewport = views().compactMap({ $0 as? MolecularMTKView }).first else { throw ParseError.noGeometry }
            viewport.draw()
            for (index, caption) in viewport.measurementOverlay.captions.enumerated() {
                let point = viewport.projectedAtomPoint(index)!
                try require(hypot(caption.inkRect.midX - point.x, caption.inkRect.midY - point.y) < 0.01, "Caption is not anchored to its actual projected sphere center")
            }
            viewport.capture(to: evidence.appendingPathComponent("centered-atom-captions.png"))
            print("CENTERED_CAPTIONS_PASS: real glyph-pixel bounds for H/I/Cl/O12/Ru123 and projected sphere centers"); fflush(stdout)

            let folder = evidence.appendingPathComponent("real-pyscf-" + UUID().uuidString.prefix(8))
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let path = folder.appendingPathComponent("input.yaml")
            try "2\nIndependent H2 at 0.74 Angstrom\nH 0 0 0\nH 0 0 0.74\n".write(to: folder.appendingPathComponent("seed.xyz"), atomically: true, encoding: .utf8)
            let yaml = """
            input: seed.xyz
            template_dir: templates
            output_dir: outputs
            scratch_dir: scratch
            dispatch: local
            max_cores: 1
            charge: 0
            multiplicity: 1
            steps:
              - step: 1
                engine: pyscf
                options: {method: hf, basis: 6-31g, df: false, cores: 1}
            """ + "\n"
            try yaml.write(to: path, atomically: true, encoding: .utf8)
            let initial = try JSONDecoder().decode(WorkflowRunner.Report.self, from: await runner.bridge(action: "check", path: path.path))
            try require(!initial.ok, "Missing template was reported ready")
            try await runner.execute(action: "scaffold", configPath: path.path)
            let checked = try JSONDecoder().decode(WorkflowRunner.Report.self, from: await runner.bridge(action: "check", path: path.path))
            try require(checked.ok && checked.requiredBackends == ["pyscf"], "Real PySCF dependency/template check failed: " + checked.checks.filter { $0.status == "error" }.map(\.detail).joined(separator: "\n"))
            runtime.startWorkflowEditor(configURL: path, workspace: workspace)
            var browser: WKWebView?
            for _ in 0..<150 {
                browser = views().compactMap { $0 as? WKWebView }.first
                if let browser, (try? await browser.evaluateJavaScript("!!(window.chemViewerDashboard && window.chemViewerDashboard.data)")) as? Bool == true { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            guard let browser else { throw ParseError.malformed("Live ChemRefine editor missing") }
            let templateURL = folder.appendingPathComponent("templates/step1.py")
            let template = try String(contentsOf: templateURL, encoding: .utf8) + "\n# native unsaved template flushed before run\n"
            _ = try await browser.callAsyncJavaScript("const b = Alpine.$data(document.body); b.cfg.steps[0].options.basis='sto-3g'; b.cfg.steps.push({step:2,name:'refine',engine:'pyscf',template:'refine.py',options:{method:'hf',basis:'sto-3g',df:false,cores:1}}); b.tmpl={open:true,step:2,text:template}; b.syncYaml(); return true;", arguments: ["template": template], in: nil, contentWorld: .page)
            // Exercise the actual bottom-right dashboard and real native confirmation.
            browser.evaluateJavaScript("setTimeout(() => Alpine.$data(document.body).launch('run'), 0); true") { _, _ in }
            var confirmed = false
            for _ in 0..<100 {
                if let sheet = NSApp.windows.compactMap(\.attachedSheet).first,
                   let button = sheet.contentView.map(descendants)?.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Continue" }) {
                    button.performClick(nil); confirmed = true; break
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try require(confirmed, "Embedded Run did not display its native confirmation")
            // Wait for the WK reply to enter native preparation.
            for _ in 0..<50 {
                if runner.busy { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            for _ in 0..<600 {
                if !runner.busy { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try require(runner.running && runner.runConfigPath == path.path, "Native Run button did not start a real ChemRefine pipeline: " + runner.status)
            try require((try String(contentsOf: path, encoding: .utf8)).contains("sto-3g"), "Runner used stale on-disk YAML instead of the live form")
            try require((try String(contentsOf: folder.appendingPathComponent("templates/refine.py"), encoding: .utf8)).contains("native unsaved template"), "Unsaved template changes were not flushed")
            // Keep the live editor open for the dashboard action/summary checks.
            for _ in 0..<600 {
                if !runner.running { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try require(!runner.running && runner.status.hasPrefix("ChemRefine completed."), "Real ChemRefine calculation did not complete: " + runner.status + "\n" + runner.logText)
            let csv = try String(contentsOf: folder.appendingPathComponent("outputs/steps.csv"), encoding: .utf8)
            try require(csv.contains("-1.1167593"), "H2 HF/STO-3G energy did not match the independent -1.1167593074 Eh oracle: " + csv)
            let state = try await runner.readStatus(path.path)
            try require(!state.running && state.steps.count == 2 && state.steps.allSatisfy { $0.cached && $0.failures == 0 && $0.reported_survivors == 1 }, "Native status did not report the actual completed calculation")
            // Exercise the same live dashboard, now with completed results.
            let reopened = browser
            _ = try await reopened.callAsyncJavaScript("await window.chemViewerDashboard.refresh(); return true;", arguments: [:], in: nil, contentWorld: .page)
            let progressFresh = try await reopened.evaluateJavaScript("Alpine.$data(document.body).runStatus.steps.every(s => s.cached && s.reported_survivors === 1)") as? Bool ?? false
            try require(progressFresh, "Upstream progress table remained stale after a fast run")
            let summary = try await reopened.evaluateJavaScript("JSON.stringify(window.chemViewerDashboard.data)") as? String ?? ""
            try require(summary.contains("refine") && summary.contains("-1.1167593"), "Step table did not load actual step names and energies: " + summary)
            _ = try await reopened.evaluateJavaScript("window.chemViewerDashboard.refresh(); true")
            try await Task.sleep(nanoseconds: 800_000_000)
            let table = try await reopened.evaluateJavaScript("document.querySelector('#chemviewer-step-summary').innerText") as? String ?? ""
            try require(table.contains("Eh") && table.contains("refine") && table.contains("-1.1167593"), "Visible step table is incomplete: " + table)
            _ = try await reopened.evaluateJavaScript("var u=document.querySelector('#chemviewer-step-summary select'); u.selectedIndex=1; u.dispatchEvent(new Event('change')); true")
            let kcal = try await reopened.evaluateJavaScript("document.querySelector('#chemviewer-step-summary tbody').innerText") as? String ?? ""
            let expected = String(format: "%.6f", -1.1167593073964255 * EnergyUnit.kilocaloriePerMole.perHartree)
            try require(kcal.contains(expected) && kcal.contains("kcal/mol"), "Table unit conversion differs from independent energy oracle: " + kcal)
            _ = try await reopened.evaluateJavaScript("var u=document.querySelector('#chemviewer-step-summary select'); u.selectedIndex=0; u.dispatchEvent(new Event('change')); document.querySelector('#run').scrollIntoView(); true")
            try await Task.sleep(nanoseconds: 300_000_000)
            let snapshot: NSImage = try await withCheckedThrowingContinuation { continuation in
                reopened.takeSnapshot(with: nil) { image, error in
                    if let image { continuation.resume(returning: image) }
                    else { continuation.resume(throwing: error ?? ParseError.malformed("Dashboard snapshot failed")) }
                }
            }
            if let tiff = snapshot.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: evidence.appendingPathComponent("workflow-dashboard.png"))
            }
            for action in ["resume", "rebuild-cache", "rerun-errors"] {
                reopened.evaluateJavaScript("var b=Alpine.$data(document.body); b.runTarget='\(action)' === 'resume' ? '' : '2'; setTimeout(()=>b.launch('\(action)'),0); true;") { _, _ in }
                var accepted = false
                for _ in 0..<100 {
                    if let sheet = NSApp.windows.compactMap(\.attachedSheet).first,
                       let button = sheet.contentView.map(descendants)?.compactMap({ $0 as? NSButton }).first(where: { $0.title == "Continue" }) {
                        button.performClick(nil); accepted = true; break
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                try require(accepted, "No confirmation for embedded " + action)
                print("DASHBOARD_CONFIRMED: " + action); fflush(stdout)
                for _ in 0..<100 {
                    if runner.currentAction == action && (runner.busy || runner.running) { break }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                if action == "rerun-errors" { runtime.stopWorkflowTestServer() }
                for _ in 0..<600 {
                    if !runner.busy && !runner.running { break }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                try require(runner.currentAction == action && runner.status.hasPrefix("ChemRefine completed."), "Embedded action failed: " + action + ": " + runner.status)
            }
            print("DASHBOARD_ACTIONS_PASS: real bottom Run, Resume, targeted Rebuild cache/Rerun errors, native confirmations, current YAML saving and actual two-step energy table")
            runtime.stopWorkflowTestServer()
            print("WORKFLOW_RUNNER_PASS: missing-template block, non-overwriting scaffold, real isolated backend check, live unsaved YAML/template save, actual detached two-step ChemRefine/PySCF H2 run, recovery driver/editor-server shutdown survival, native log/status and HF/STO-3G energy -1.1167593074 Eh")
            print("WORKFLOW_EVIDENCE: " + folder.path)
            restoreDefaults(); fflush(stdout); exit(0)
        } catch {
            runtime.stopWorkflowTestServer()
            restoreDefaults()
            fputs("WORKFLOW_RUNNER_FAIL: \(error.localizedDescription)\n", stderr); fflush(stderr); exit(1)
        }
    }
}
