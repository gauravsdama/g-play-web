// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "VantabeatMac",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "VantabeatMac", targets: ["VantabeatMac"]),
    ],
    targets: [
        .executableTarget(
            name: "VantabeatMac",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
