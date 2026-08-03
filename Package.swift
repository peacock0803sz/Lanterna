// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Lanterna",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        .executableTarget(name: "Lanterna"),
        .testTarget(name: "LanternaTests", dependencies: ["Lanterna"]),
    ]
)
