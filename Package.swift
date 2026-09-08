// swift-tools-version: 5.9

import PackageDescription

let sfioraVersion = "1.0.0"
let sfioraReleaseBaseURL =
    "https://github.com/sandroxy/sfiora/releases/download/\(sfioraVersion)"
let sfioraBinaryURL = "\(sfioraReleaseBaseURL)/sfiora-\(sfioraVersion).xcframework.zip"
let sfioraBinaryChecksum =
    "ccd699da75ad342600c6a3562a223b20e02c9af1b0f0690379ef51c8f2d21cf6"

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
