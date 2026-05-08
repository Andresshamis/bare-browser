// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MeridianBrowser",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "MeridianBrowser", targets: ["MeridianBrowser"]),
        .library(name: "MeridianCore", targets: ["MeridianCore"])
    ],
    targets: [
        .target(
            name: "MeridianCore",
            path: "Sources/MeridianCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "MeridianBrowser",
            dependencies: ["MeridianCore"],
            path: "Sources/MeridianBrowser"
        ),
        .testTarget(
            name: "MeridianBrowserTests",
            dependencies: ["MeridianCore"],
            path: "Tests/MeridianBrowserTests"
        )
    ]
)
