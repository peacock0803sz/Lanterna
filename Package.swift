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
        // Vendored romaji matching engine. The version pin stays out
        // of the build; tables ride as resources beside the product.
        .target(
            name: "CMigemo",
            exclude: ["VERSION"],
            resources: [.copy("tables")],
            cSettings: [.unsafeFlags(["-w"])]
        ),
        .executableTarget(name: "Lanterna", dependencies: ["PrivateAPIs", "CMigemo"]),
        .testTarget(
            name: "LanternaTests",
            dependencies: ["Lanterna"]
        ),
    ]
)
