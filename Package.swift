// swift-tools-version: 5.9

import PackageDescription

// Published binary pin. Advance with the checksum of the next clean archive
// during the two-commit release handoff; source development uses native/ios.
let sfioraVersion = "1.1.0"
let sfioraReleaseBaseURL =
    "https://github.com/sandroxy/sfiora/releases/download/\(sfioraVersion)"
let sfioraBinaryURL = "\(sfioraReleaseBaseURL)/sfiora-\(sfioraVersion).xcframework.zip"
let sfioraBinaryChecksum =
    "3e1cb0af3892a49dbef4f9fd5bb74ed4dcc1129dd2e0a11410c52ee57355ae2b"

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
