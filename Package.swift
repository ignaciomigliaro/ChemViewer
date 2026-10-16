// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChemViewer",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ChemCraftCore", targets: ["ChemCraftCore"]),
        .executable(name: "ChemViewer", targets: ["ChemViewerApp"])
    ],
    targets: [
        .target(name: "ChemCraftCore"),
        .executableTarget(
            name: "ChemViewerApp",
            dependencies: ["ChemCraftCore"],
            path: "Sources/ChemCraftMacApp",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "ChemCraftCoreTests", dependencies: ["ChemCraftCore"])
    ]
)
