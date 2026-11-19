// swift-tools-version: 6.2
// xtool adapter for the "Smart Tube" tvOS target (SmartTubeApp.xcodeproj), so the app builds
// and signs on Linux with omarchy-apple-dev. Started from tools/xcodeproj2xtool.py output.
import PackageDescription

let package = Package(
    name: "Smart Tube",
    defaultLocalization: "en",
    platforms: [.iOS("17.0"), .tvOS("17.6")],
    products: [
        .library(name: "Smart Tube", targets: ["Smart Tube"])
    ],
    dependencies: [
        .package(name: "SmartTubeIOS", path: "../../SmartTubeIOS")
    ],
    targets: [
        .target(
            name: "Smart Tube",
            dependencies: [
                .product(name: "SmartTubeIOS", package: "SmartTubeIOS")
            ],
            resources: [
                .process("Smart Tube/Assets.xcassets")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
