// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [
    .library(name: "ChemCraftCore", targets: ["ChemCraftCore"]),
    .executable(name: "ChemViewerPortable", targets: ["ChemViewerPortable"])
]
var targets: [Target] = [
    .target(name: "ChemCraftCore"),
    .executableTarget(name: "ChemViewerPortable", dependencies: ["ChemCraftCore"], resources: [.copy("viewer.html")]),
    .testTarget(name: "ChemCraftCoreTests", dependencies: ["ChemCraftCore"]),
    .testTarget(name: "IntegratedBuildingTests", dependencies: ["ChemCraftCore"], path: "Tests/IntegratedBuilding")
]
#if os(macOS)
products.append(.executable(name: "ChemViewer", targets: ["ChemViewerApp"]))
targets.append(.executableTarget(
    name: "ChemViewerApp", dependencies: ["ChemCraftCore"],
    path: "Sources/ChemCraftMacApp",
    exclude: ["Resources/__pycache__"],
    resources: [.copy("Resources/MoleculeShaders.metal")] + ["Fragments.json", "workflow_dashboard.js",
                "remote_agent.py", "remote_bridge.py", "chemistry_bridge.py",
                "drawing_bridge.py", "bostmc_catalog.py", "energy_landscape.py",
                "workflow_bridge.py"].map { .process("Resources/" + $0) }
))
#endif

let package = Package(
    name: "ChemViewer",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets
)
