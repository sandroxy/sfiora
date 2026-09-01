// swift-tools-version: 5.9

import PackageDescription

let sfioraVersion = "1.0.0"
let sfioraReleaseBaseURL =
    "https://github.com/sandroxy/sfiora/releases/download/\(sfioraVersion)"
let sfioraBinaryURL = "\(sfioraReleaseBaseURL)/sfiora-\(sfioraVersion).xcframework.zip"
let sfioraBinaryChecksum =
    "b41f73f040569923ee160b03a3cebfdfc04b13c82f57235c454f30fa8052e71f"

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
