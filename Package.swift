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
        // Vendored romaji matching engine. Tables and the version pin are
        // kept out of the build; the wrapper locates them at runtime.
        .target(
            name: "CMigemo",
            exclude: ["tables", "VERSION"]
        ),
        .executableTarget(name: "Lanterna", dependencies: ["PrivateAPIs", "CMigemo"]),
        .testTarget(
            name: "LanternaTests",
            dependencies: ["Lanterna"]
        ),
    ]
)
