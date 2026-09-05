// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SonosKit",
    platforms: [.macOS("15.0")],
    products: [
        .library(name: "SonosKit", targets: ["SonosKit"]),
        .executable(name: "sonosctl", targets: ["sonosctl"]),
    ],
    targets: [
        .target(name: "SonosKit"),
        .executableTarget(name: "sonosctl", dependencies: ["SonosKit"]),
        .testTarget(
            name: "SonosKitTests",
            dependencies: ["SonosKit"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
