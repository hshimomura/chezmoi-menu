// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChezmoiMenu",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ChezmoiMenu", targets: ["ChezmoiMenu"])],
    targets: [
        .target(name: "ChezmoiCore"),
        .executableTarget(name: "ChezmoiMenu", dependencies: ["ChezmoiCore"]),
        .testTarget(name: "ChezmoiCoreTests", dependencies: ["ChezmoiCore"])
    ],
    swiftLanguageModes: [.v5]
)
