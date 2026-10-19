import AppKit
import ChemCraftCore

@MainActor enum NEBSmokeTest {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        do {
            func check(_ value: Bool, _ text: String) throws { if !value { throw AnimationExportError.message(text) } }
            let args = CommandLine.arguments
            guard let inputIndex = args.firstIndex(of: "--neb-input"), args.indices.contains(inputIndex + 1) else { throw AnimationExportError.message("Provide --neb-input output.out") }
            let input = URL(fileURLWithPath: args[inputIndex + 1])
            let evidence = URL(fileURLWithPath: "/Users/nacho/Downloads/chemviewer-neb-work")
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
            workspace.open(input)
            for _ in 0..<2400 { if !workspace.isLoading { break }; try await Task.sleep(nanoseconds: 25_000_000) }
            try check(workspace.errorMessage == nil && !workspace.isLoading, workspace.errorMessage ?? "NEB input timed out")
            guard let document = workspace.document, let profile = document.nebProfile else { throw AnimationExportError.message("NEB summary missing") }
            try check(profile.images.count == 11 && profile.tsConverged, "Final NEB-TS summary not selected")
            try check(abs((profile.forwardBarrierKcal ?? 0) - 86.35) < 1e-8 && abs((profile.reverseBarrierKcal ?? 0) - 2.66) < 1e-8, "Refined TS barriers differ from printed output")
            try check(abs(profile.reactionEnergyKcal - 83.69) < 1e-8, "Reaction energy differs from printed output")
            var options = EnergyPlotOptions.initial(for: document)
            try check(options.neb && options.plotStyle == "diagram" && !options.markers, "NEB defaults not selected")
            let request = try options.request(workspace: workspace)
            try check(request.points.count == 3 && request.tsIndex == 1 && request.points.map(\.relativeEnergyKcal) == [0, 86.35, 83.69], "Reaction diagram contains optimization cycles or CI energy")
            try check(request.points.allSatisfy { !$0.atoms.isEmpty }, "Matched endpoint/TS companion structures missing")
            let directory = try await MatplotlibRunner.render(request)
            let target = evidence.appendingPathComponent("TS-reaction-diagram")
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
            try FileManager.default.copyItem(at: directory, to: target)
            try? FileManager.default.removeItem(at: directory)
            let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: target.appendingPathComponent("plot-metadata.json"))) as! [String: Any]
            let barriers = metadata["barriers"] as! [String: Any]
            try check(abs((barriers["reverse"] as! Double) - 2.66) < 1e-8, "Rendered barrier metadata incorrect")
            options.nebContent = "images"; options.plotStyle = "profile"
            let full = try options.request(workspace: workspace)
            try check(full.points.count == 11 && full.tsIndex == 5, "Full NEB band missing images or refined TS")
            let fullDirectory = try await MatplotlibRunner.render(full)
            let fullTarget = evidence.appendingPathComponent("TS-full-neb-path")
            if FileManager.default.fileExists(atPath: fullTarget.path) { try FileManager.default.removeItem(at: fullTarget) }
            try FileManager.default.copyItem(at: fullDirectory, to: fullTarget); try? FileManager.default.removeItem(at: fullDirectory)
            options.neb = false
            let optimization = try options.request(workspace: workspace)
            try check(optimization.points.count == document.frames.count && optimization.dataSource == "optimization", "TS optimization toggle failed")
            workspace.isEnergyLandscapePresented = true
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try check(NSApp.windows.contains { $0.sheetParent != nil }, "NEB plot sheet did not present")
            print("NEB_SMOKE_PASS: user's TS.out, final 11-row summary, 86.35/2.66/83.69 kcal/mol, three matching structures, auto defaults, reaction/full-band plots, optimization toggle, native sheet")
            exit(0)
        } catch { fputs("NEB_SMOKE_FAIL: \(error)\n", stderr); exit(1) }
    }
}
