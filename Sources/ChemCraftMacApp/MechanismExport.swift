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
        let (config, files, overrides) = try makePackage()
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
        _ = try await WorkflowRunner.shared.bridge(action: "write-mechanism-yaml", path: yaml.path, fields: ["overrides": overrides])
        try manager.moveItem(at: staging, to: destination)
        return destination.appendingPathComponent("input.yaml")
    }

    func previewYAML() async throws -> String {
        let (config, _, overrides) = try makePackage()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("input.yaml")
        let data = try await WorkflowRunner.shared.bridge(
            action: "preview-mechanism-yaml", path: url.path, fields: ["config": config, "overrides": overrides]
        )
        struct Preview: Decodable { let yaml: String }
        return try JSONDecoder().decode(Preview.self, from: data).yaml
    }

    private func makePackage() throws -> ([String: Any], [String: String], [[String: Any]]) {
        guard let variantCount, variantCount <= maxVariants else {
            throw ParseError.malformed("Reduce the combinations or raise the variant limit of \(maxVariants).")
        }
        guard (1...cores).contains(workers) else {
            throw ParseError.malformed("Set parallel mechanisms to at most the total CPU budget.")
        }

        var files = ["templates/cpu.slurm.header": "#!/bin/bash\n"]
        var stageConfigs: [[String: Any]] = []
        var stageNames: [UUID: String] = [:]
        var overrides: [[String: Any]] = []

        func addOverride(_ path: [String], _ yaml: String) {
            if !yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                overrides.append(["path": path, "yaml": yaml])
            }
        }

        func calculations(_ steps: [MechanismCalculation], _ branch: MechanismBranch,
                          stageNumber: Int, path: [String]) throws -> [[String: Any]] {
            try steps.enumerated().map { offset, calculation in
                let number = offset + 1
                let engine = calculation.engine
                let descriptor = schema?.engines[engine]
                guard descriptor != nil || engine == "orca" else {
                    throw ParseError.malformed("Load the ChemRefine engine registry before exporting \(engine).")
                }
                var step: [String: Any] = ["step": number, "engine": engine, "on_failure": calculation.onFailure]
                if calculation.nms { step["nms"] = true }
                let name = calculation.name.trimmingCharacters(in: .whitespaces)
                let operation = calculation.operation.trimmingCharacters(in: .whitespaces)
                let method = calculation.method.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { step["name"] = name }
                if !operation.isEmpty { step["operation"] = operation }
                var options: [String: String] = [:]
                if let key = descriptor?.methodOption, !method.isEmpty { options[key] = method }
                if engine == "mlip-extopt", method.hasPrefix("uma") {
                    options["task_name"] = "omol"
                    options["device"] = "cpu"
                    let python = WorkflowRunner.shared.resolvedUMAPython
                    if !python.isEmpty { options["backend_python"] = python }
                }
                if !options.isEmpty { step["options"] = options }
                if let suffix = descriptor?.templateSuffix ?? (engine == "orca" ? "inp" : nil) {
                    let filename = "stage_\(stageNumber)_\(branch.rawValue)_\(number).\(suffix)"
                    let custom = calculation.template.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !custom.isEmpty {
                        files["templates/\(filename)"] = calculation.template
                    } else if suffix == "inp", engine == "orca" || engine.hasSuffix("-extopt") {
                        let keyword = engine == "orca" ? method : "ExtOpt"
                        let frequency = engine.hasSuffix("-extopt") ? "NumFreq" : "Freq"
                        let directive: String
                        switch operation {
                        case "sp": directive = ""
                        case "freq": directive = frequency
                        case "": directive = branch == .ts ? "OptTS TightOpt " + frequency : "Opt TightOpt"
                        case "opt_sp": directive = branch == .ts ? "OptTS TightOpt" : "Opt TightOpt"
                        default: directive = "" // Specialized operations use the engine template entered by the user.
                        }
                        if ["", "sp", "freq", "opt_sp"].contains(operation), !keyword.isEmpty {
                            let isTS = branch == .ts && ["", "opt_sp"].contains(operation)
                            let hessian = engine == "orca" ? "" : "  NumHess true\n"
                            let block = isTS ? "%geom\n  Calc_Hess true\n\(hessian)end\n" : ""
                            files["templates/\(filename)"] = "! " + [keyword, directive].filter { !$0.isEmpty }.joined(separator: " ") + "\n" + block
                        } else if calculation.settingsYAML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            throw ParseError.malformed("Enter template contents for \(branch.label) calculation \(number).")
                        }
                    } else if let starter = descriptor?.starter {
                        var content = starter
                        if engine == "qchem" {
                            if !method.isEmpty {
                                content = content.replacingOccurrences(of: "  method      b3lyp", with: "  method      " + method)
                            }
                            let job: String = operation == "freq" ? "freq" : (operation == "sp" ? "sp" : (branch == .ts ? "ts" : "opt"))
                            content = content.replacingOccurrences(of: "  jobtype     opt", with: "  jobtype     " + job)
                        }
                        files["templates/\(filename)"] = content
                    }
                    step["template"] = filename
                }
                addOverride(path + [String(offset)], calculation.settingsYAML)
                return step
            }
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
            guard !sources.isEmpty || !stage.reactantYAML.isEmpty || !stage.settingsYAML.isEmpty || !mechanismYAML.isEmpty || !workflowYAML.isEmpty else {
                throw ParseError.malformed("Add a reactant source for \(name).")
            }
            let path = ["mechanism", "stages", String(index)]
            let stageNumber = index + 1
            var reactant: [String: Any] = [
                "sources": sources, "steps": try calculations(stage.reactantSteps, .reactant, stageNumber: stageNumber, path: path + ["reactant", "steps"])
            ]
            if let core = stage.initialCore {
                reactant["initial_core"] = coreConfig(core, path: folder + "/initial_core.xyz")
            }
            var product: [String: Any] = [
                "steps": try calculations(stage.productSteps, .product, stageNumber: stageNumber, path: path + ["product", "steps"])
            ]
            let customProduct = !stage.productYAML.isEmpty || !stage.settingsYAML.isEmpty || !mechanismYAML.isEmpty || !workflowYAML.isEmpty
            switch stage.productKind {
            case .core:
                guard let core = stage.productCore else {
                    if customProduct { break }
                    throw ParseError.malformed("Add a product core for \(name).")
                }
                product["core"] = coreConfig(core, path: folder + "/product_core.xyz")
            case .xyz:
                guard let xyz = stage.productXYZ else {
                    if customProduct { break }
                    throw ParseError.malformed("Add a complete product XYZ for \(name).")
                }
                let path = folder + "/product.xyz"
                files[path] = xyz.xyz
                product["input"] = path
            case .smiles:
                let smiles = stage.productSMILES.trimmingCharacters(in: .whitespacesAndNewlines)
                if !smiles.isEmpty { product["smiles"] = smiles }
                else if !customProduct { throw ParseError.malformed("Enter the complete product SMILES for \(name).") }
            }
            stageConfigs.append([
                "name": name, "charge": charge, "multiplicity": multiplicity, "reactant": reactant,
                "product": product, "ts_guesser": [
                    "method": stage.guesser, "n_images": stage.images, "timeout_seconds": stage.guesserTimeout,
                    "scoring_steps": try calculations(stage.scoringSteps, .scoring, stageNumber: stageNumber, path: path + ["ts_guesser", "scoring_steps"])
                ], "ts_steps": try calculations(stage.tsSteps, .ts, stageNumber: stageNumber, path: path + ["ts_steps"])
            ])
            addOverride(path, stage.settingsYAML)
            addOverride(path + ["reactant"], stage.reactantYAML)
            addOverride(path + ["product"], stage.productYAML)
            addOverride(path + ["ts_guesser"], stage.guesserYAML)
            stageNames[stage.id] = name
        }

        let orca = WorkflowRunner.shared.orcaPath
        var mechanism: [String: Any] = ["parallel_runs": workers, "max_variants": maxVariants, "stages": stageConfigs]
        if forceMetalContacts { mechanism["force"] = true }
        let config: [String: Any] = [
            "dispatch": "local", "template_dir": "templates", "output_dir": "outputs",
            "max_cores": cores, "max_gpus": maxGPUs, "executables": ["orca": orca.isEmpty ? "orca" : orca],
            "mechanism": mechanism
        ]
        addOverride(["mechanism"], mechanismYAML)
        addOverride([], workflowYAML)
        return (config, files, overrides)
    }
}
