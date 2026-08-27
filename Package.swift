// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Sfiora",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "Sfiora",
            targets: ["Sfiora"]
        )
    ],
    targets: [
        .target(
            name: "Sfiora",
            path: "native/ios/Sources/Sfiora"
        ),
        .testTarget(
            name: "SfioraTests",
            dependencies: ["Sfiora"],
            path: "tests",
            sources: ["ios"],
            resources: [
                .process("fixtures/ndef-vectors.json")
            ]
        ),
    ],
    swiftLanguageVersions: [.v5]
)
