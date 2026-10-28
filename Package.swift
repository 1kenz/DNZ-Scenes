// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DNZ-Scenes",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ScenesCore", targets: ["ScenesCore"]),
        .executable(name: "DNZScenes", targets: ["DNZScenes"]),
        .executable(name: "ScenesCoreChecks", targets: ["ScenesCoreChecks"])
    ],
    targets: [
        .target(name: "ScenesCore"),
        .executableTarget(name: "DNZScenes", dependencies: ["ScenesCore"]),
        // Dependency-free checks (works with Command Line Tools only; no XCTest needed).
        .executableTarget(name: "ScenesCoreChecks", dependencies: ["ScenesCore"])
    ]
)
