// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Lanterna",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        // Declarations of the private ApplicationServices functions the app is
        // allowed to call. Kept in C because Swift has no supported way to
        // declare them.
        .target(name: "PrivateAPIs"),
        .executableTarget(name: "Lanterna", dependencies: ["PrivateAPIs"]),
        .testTarget(
            name: "LanternaTests",
            dependencies: ["Lanterna"]
        ),
    ]
)
