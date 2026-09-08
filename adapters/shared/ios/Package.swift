// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SfioraBridgeSupport",
    platforms: [
        .iOS(.v13),
        .macOS(.v12),
    ],
    products: [
        .library(
            name: "SfioraBridgeSupport",
            targets: ["SfioraBridgeSupport"]
        )
    ],
    dependencies: [
        .package(name: "SfioraSource", path: "../../../native/ios")
    ],
    targets: [
        .target(
            name: "SfioraBridgeSupport",
            dependencies: [
                .product(name: "Sfiora", package: "SfioraSource")
            ]
        ),
        .testTarget(
            name: "SfioraBridgeSupportTests",
            dependencies: ["SfioraBridgeSupport"]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
