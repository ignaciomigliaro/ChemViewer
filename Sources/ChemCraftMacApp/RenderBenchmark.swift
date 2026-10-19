import AppKit
import ChemCraftCore

@MainActor
enum RenderBenchmark {
    static var started = false
    static func run(workspace: WorkspaceStore) async {
        guard !started else { return }; started = true
        do {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("benchmark-\(UUID().uuidString).xyz")
            let count = 500
            let rows = (0..<count).map { "C \(Float($0 % 10) * 1.5) \(Float(($0 / 10) % 10) * 1.5) \(Float($0 / 100) * 1.5)" }
            try ("\(count)\nsynthetic render benchmark\n" + rows.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
            workspace.open(file)
            for _ in 0..<200 { if !workspace.isLoading { break }; try await Task.sleep(nanoseconds: 30_000_000) }
            try await Task.sleep(nanoseconds: 200_000_000)
            func find(_ root: NSView) -> MolecularMTKView? {
                if let view = root as? MolecularMTKView { return view }
                return root.subviews.lazy.compactMap(find).first
            }
            guard let view = NSApp.windows.compactMap(\.contentView).compactMap(find).first, view.renderingReady else { throw CocoaError(.coderReadCorrupt) }
            var times: [Double] = []
            for index in 0..<25 {
                let start = CACurrentMediaTime(); view.draw()
                let elapsed = (CACurrentMediaTime() - start) * 1000
                if index >= 5 { times.append(elapsed) }
                try await Task.sleep(nanoseconds: 30_000_000)
            }
            times.sort()
            print("Render benchmark: 500 atoms, CPU draw median=\(times[times.count / 2]) ms, p95=\(times[Int(Double(times.count - 1) * 0.95)]) ms, completedFrames=\(view.completedFrameCount)")
            try? FileManager.default.removeItem(at: file)
            fflush(stdout); exit(0)
        } catch { fputs("Render benchmark FAIL: \(error)\n", stderr); exit(1) }
    }
}
