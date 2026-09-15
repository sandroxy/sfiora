// swift-tools-version: 5.9

import PackageDescription

// Published binary pin. Advance with the checksum of the next clean archive
// during the two-commit release handoff; source development uses native/ios.
let sfioraVersion = "1.2.0"
let sfioraReleaseBaseURL =
    "https://github.com/sandroxy/sfiora/releases/download/\(sfioraVersion)"
let sfioraBinaryURL = "\(sfioraReleaseBaseURL)/sfiora-\(sfioraVersion).xcframework.zip"
let sfioraBinaryChecksum =
    "2a32af45a14029d7b25c9245f6cac878802a13177870436569b4661eeb4bb8b8"

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
        .binaryTarget(
            name: "Sfiora",
            url: sfioraBinaryURL,
            checksum: sfioraBinaryChecksum
        )
    ]
)
