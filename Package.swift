// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ChezmoiMenu",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "ChezmoiMenu", targets: ["ChezmoiMenu"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", .upToNextMinor(from: "1.0.0"))
    ],
    targets: [
        .target(name: "ChezmoiCore", dependencies: [.product(name: "Subprocess", package: "swift-subprocess")]),
        .executableTarget(name: "ChezmoiMenu", dependencies: ["ChezmoiCore"]),
        .testTarget(name: "ChezmoiCoreTests", dependencies: ["ChezmoiCore"])
    ],
    swiftLanguageModes: [.v6]
)
