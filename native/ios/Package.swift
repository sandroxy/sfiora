// swift-tools-version: 5.9

import PackageDescription

// Development-only source package. The repository root publishes the binary package.
let package = Package(
    name: "SfioraSource",
    platforms: [.iOS(.v13), .macOS(.v12)],
    products: [.library(name: "Sfiora", targets: ["Sfiora"])],
    targets: [.target(name: "Sfiora", path: "Sources/Sfiora")],
    swiftLanguageVersions: [.v5]
)
