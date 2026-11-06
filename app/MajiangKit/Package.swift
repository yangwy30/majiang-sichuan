// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MajiangKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MajiangKit", targets: ["MajiangKit"]),
    ],
    targets: [
        .target(
            name: "MajiangKit"
        ),
        .testTarget(
            name: "MajiangKitTests",
            dependencies: ["MajiangKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
