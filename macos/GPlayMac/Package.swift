// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "GPlayMac",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "GPlayMac", targets: ["GPlayMac"]),
    ],
    targets: [
        .executableTarget(
            name: "GPlayMac",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
