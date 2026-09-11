// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Lanterna",
    platforms: [
        .macOS(.v26),
    ],
    targets: [
        // Declarations of the private system functions the app calls; the
        // case for each is made in the header. Kept in C because Swift has no
        // supported way to declare them.
        .target(name: "PrivateAPIs"),
        .executableTarget(name: "Lanterna", dependencies: ["PrivateAPIs"]),
        .testTarget(
            name: "LanternaTests",
            dependencies: ["Lanterna"]
        ),
    ]
)
