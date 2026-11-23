import Foundation

enum MechanismBranch: String {
    case reactant, product, scoring, ts

    var label: String {
        switch self {
        case .reactant: "Reactant preparation"
        case .product: "Product preparation"
        case .scoring: "Path scoring"
        case .ts: "TS refinement"
        }
    }

    var defaultOperation: String {
        switch self {
        case .scoring: "sp"
        case .reactant, .product: "opt_sp"
        case .ts: ""
        }
    }
}

struct MechanismCalculation: Identifiable {
    let id = UUID()
    var name = ""
    var engine = "orca"
    var operation: String
    var method = "r2SCAN-3c"
    var template = ""
    var settingsYAML = ""
    var onFailure = "stop"
    var nms = false
    var expanded = false

    init(_ branch: MechanismBranch, expanded: Bool = false) {
        operation = branch.defaultOperation
        self.expanded = expanded
    }
}

struct MechanismSchema: Decodable {
    let engines: [String: Engine]
    let config: ObjectSchema
    let nms: ObjectSchema

    struct ObjectSchema: Decodable {
        let properties: [String: Field]?
        let definitions: [String: ObjectSchema]?
        enum CodingKeys: String, CodingKey { case properties; case definitions = "$defs" }

        struct Field: Decodable {
            let description: String?
            let choices: [String]?
            enum CodingKeys: String, CodingKey { case description; case choices = "enum" }
            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                description = try values.decodeIfPresent(String.self, forKey: .description)
                choices = try? values.decode([String].self, forKey: .choices)
            }
        }

        var keys: [String] { (properties ?? [:]).keys.sorted() }
    }

    struct Engine: Decodable {
        let name: String
        let operations: [String]
        let templateSuffix: String?
        let optionsSchema: ObjectSchema?
        let capabilities: [String]
        // ChemRefine's scaffold provides the engine's own starter and output contract.
        let starter: String?

        enum CodingKeys: String, CodingKey {
            case name, operations, capabilities, starter
            case templateSuffix = "template_suffix"
            case optionsSchema = "options_schema"
        }

        var methodOption: String? {
            let keys = optionsSchema?.keys ?? []
            if keys.contains("method") { return "method" }
            if keys.contains("model_name") { return "model_name" }
            return nil
        }
    }

    func keys(_ definition: String? = nil) -> [String] {
        if let definition { return config.definitions?[definition]?.keys ?? [] }
        return config.keys
    }

    var guessers: [String] {
        config.definitions?["TSGuesserConfig"]?.properties?["method"]?.choices ?? ["idpp", "geodesic", "fragmentflow", "react-ot", "external"]
    }
}
