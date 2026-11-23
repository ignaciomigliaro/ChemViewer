import AppKit
import ChemCraftCore
import Foundation

extension MechanismDraft {
    func save(_ workspace: WorkspaceStore) {
        guard !saving else { return }
        guard ChemistryRuntime.shared.installed else {
            notice = "Install the ChemViewer chemistry runtime with scripts/setup-chemistry.sh."
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose a parent folder for the new mechanism, its XYZ files and templates."
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        saving = true
        notice = "Writing input.yaml and its geometry files…"
        Task {
            defer { saving = false }
            do {
                let url = try await export(to: parent)
                savedURL = url
                visible = false
                ChemistryRuntime.shared.openLocalWorkflow(url, workspace: workspace)
            } catch { notice = error.localizedDescription }
        }
    }

    func export(to parent: URL) async throws -> URL {
        let (config, files) = try makePackage()
        let key = UUID().uuidString
        let staging = parent.appendingPathComponent(".ChemViewer-mechanism-" + key)
        let destination = parent.appendingPathComponent("ChemViewer-mechanism-" + key.prefix(8))
        let manager = FileManager.default
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }
        for (relativePath, text) in files {
            let url = staging.appendingPathComponent(relativePath)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        let yaml = staging.appendingPathComponent("input.yaml")
        let data = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
        try data.write(to: yaml)
        _ = try await WorkflowRunner.shared.bridge(action: "write-mechanism-yaml", path: yaml.path)
        try manager.moveItem(at: staging, to: destination)
        return destination.appendingPathComponent("input.yaml")
    }

    private func makePackage() throws -> ([String: Any], [String: String]) {
        guard let variantCount, variantCount <= maxVariants else {
            throw ParseError.malformed("Reduce the combinations or raise the variant limit of \(maxVariants).")
        }
        guard (1...cores).contains(workers) else {
            throw ParseError.malformed("Set parallel mechanisms to at most the total CPU budget.")
        }

        let method = engine == .uma ? "ExtOpt" : "r2SCAN-3c"
        let minimum = "! \(method) Opt TightOpt\n"
        let scoring = "! \(method)\n"
        let hessian = engine == .uma ? "  NumHess true\n" : ""
        let frequency = engine == .uma ? "NumFreq" : "Freq"
        let ts = "! \(method) OptTS TightOpt \(frequency)\n%geom\n  Calc_Hess true\n\(hessian)end\n"
        var files = [
            "templates/minimum.inp": minimum,
            "templates/score.inp": scoring,
            "templates/ts.inp": ts,
            "templates/cpu.slurm.header": "#!/bin/bash\n"
        ]
        var stageConfigs: [[String: Any]] = []
        var stageNames: [UUID: String] = [:]

        func step(_ template: String, operation: String? = nil) -> [String: Any] {
            var step: [String: Any] = [
                "step": 1, "engine": engine == .uma ? "mlip-extopt" : "orca",
                "template": template, "on_failure": "stop"
            ]
            if let operation { step["operation"] = operation }
            if engine == .uma {
                var options = ["task_name": "omol", "model_name": "uma-s-1p2", "device": "cpu"]
                let python = WorkflowRunner.shared.resolvedUMAPython
                if !python.isEmpty { options["backend_python"] = python }
                step["options"] = options
            }
            return step
        }

        func source(_ geometries: [MechanismGeometry], folder: String, label: String) throws -> [String: Any] {
            let charges = geometries.compactMap { Int($0.charge.trimmingCharacters(in: .whitespaces)) }
            guard charges.count == geometries.count, let charge = charges.first else {
                throw ParseError.malformed("Enter the XYZ source charge for each \(label).")
            }
            guard charges.allSatisfy({ $0 == charge }),
                  Set(geometries.compactMap(\.multiplicity)).count <= 1 else {
                throw ParseError.malformed("The \(label) alternatives must share charge and spin. Use separate workflows for different electronic states.")
            }
            for (index, geometry) in geometries.enumerated() {
                let slug = geometry.name.replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "_", options: .regularExpression)
                let filename = "\(index + 1)_\(slug.prefix(60)).xyz"
                files["\(folder)/\(filename)"] = geometry.xyz
            }
            if geometries.count > 1 { return ["input_dir": folder, "charge": charge] }
            guard let path = files.keys.first(where: { $0.hasPrefix(folder + "/") }) else { throw ParseError.noGeometry }
            return ["input": path, "charge": charge]
        }

        func coreConfig(_ core: MechanismCore, path: String) -> [String: Any] {
            files[path] = core.geometry.xyz
            return ["input": path, "anchor": core.anchor, "placements": core.placements]
        }

        for (index, stage) in stages.enumerated() {
            let name = stage.name.trimmingCharacters(in: .whitespaces)
            guard name.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil,
                  !["guesser", "_inputs"].contains(name), !stageNames.values.contains(name) else {
                throw ParseError.malformed("Use unique stage names made of letters, digits, hyphens and underscores.")
            }
            guard let charge = Int(stage.charge), let multiplicity = Int(stage.multiplicity), multiplicity > 0 else {
                throw ParseError.malformed("Enter an integer charge and a positive spin multiplicity for \(name).")
            }
            let folder = "inputs/stage_\(index + 1)"
            var sources: [[String: Any]] = []
            if let carry = stage.carry {
                guard let previous = stageNames[carry] else {
                    throw ParseError.malformed("Choose an earlier stage to carry into \(name).")
                }
                var selection: [String: Any] = ["from": previous]
                switch stage.selector {
                case .whole: break
                case .metal: selection["select"] = "metal_complex"
                case .smiles:
                    let smiles = stage.selectSMILES.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !smiles.isEmpty else { throw ParseError.malformed("Enter an intermediate selector SMILES for \(name).") }
                    selection["select_smiles"] = smiles
                    if !stage.selectIndex.isEmpty {
                        guard let occurrence = Int(stage.selectIndex), occurrence >= 0 else {
                            throw ParseError.malformed("Use a zero-based occurrence for the intermediate selector in \(name).")
                        }
                        selection["select_index"] = occurrence
                    }
                }
                sources.append(selection)
            }
            if index == 0 && !catalysts.isEmpty {
                sources.append(try source(catalysts, folder: folder + "/catalysts", label: "catalyst"))
            }
            if !stage.substrates.isEmpty {
                sources.append(try source(stage.substrates, folder: folder + "/substrates", label: "substrate"))
            }
            for (offset, reagent) in stage.reagents.enumerated() {
                sources.append(try source([reagent], folder: folder + "/reagent_\(offset + 1)", label: "fixed reagent"))
            }
            guard !sources.isEmpty else { throw ParseError.malformed("Add a reactant source for \(name).") }
            var reactant: [String: Any] = ["sources": sources, "steps": [step("minimum.inp")]]
            if let core = stage.initialCore {
                reactant["initial_core"] = coreConfig(core, path: folder + "/initial_core.xyz")
            }
            var product: [String: Any] = ["steps": [step("minimum.inp")]]
            switch stage.productKind {
            case .core:
                guard let core = stage.productCore else { throw ParseError.malformed("Add a product core for \(name).") }
                product["core"] = coreConfig(core, path: folder + "/product_core.xyz")
            case .xyz:
                guard let xyz = stage.productXYZ else { throw ParseError.malformed("Add a complete product XYZ for \(name).") }
                let path = folder + "/product.xyz"
                files[path] = xyz.xyz
                product["input"] = path
            case .smiles:
                let smiles = stage.productSMILES.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !smiles.isEmpty else { throw ParseError.malformed("Enter the complete product SMILES for \(name).") }
                product["smiles"] = smiles
            }
            stageConfigs.append([
                "name": name, "charge": charge, "multiplicity": multiplicity, "reactant": reactant,
                "product": product, "ts_guesser": [
                    "method": "idpp", "n_images": images, "scoring_steps": [step("score.inp", operation: "sp")]
                ], "ts_steps": [step("ts.inp")]
            ])
            stageNames[stage.id] = name
        }

        let orca = WorkflowRunner.shared.orcaPath
        var mechanism: [String: Any] = ["parallel_runs": workers, "max_variants": maxVariants, "stages": stageConfigs]
        if forceMetalContacts { mechanism["force"] = true }
        let config: [String: Any] = [
            "dispatch": "local", "template_dir": "templates", "output_dir": "outputs",
            "max_cores": cores, "max_gpus": 0, "executables": ["orca": orca.isEmpty ? "orca" : orca],
            "mechanism": mechanism
        ]
        return (config, files)
    }
}
