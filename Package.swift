// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SlimLuma",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SlimLumaKit", targets: ["SlimLumaKit"]),
        // Keep the app build product distinct from the lowercase CLI product.
        // The bundle still installs it as Contents/MacOS/SlimLuma.
        .executable(name: "SlimLumaApp", targets: ["SlimLuma"]),
        .executable(name: "slimluma", targets: ["SlimLumaCLI"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            exact: "1.8.2"
        )
    ],
    targets: [
        .target(
            name: "SlimLumaKit"
        ),
        .executableTarget(
            name: "SlimLuma",
            dependencies: ["SlimLumaKit"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "SlimLumaCLI",
            dependencies: [
                "SlimLumaKit",
                .product(
                    name: "ArgumentParser",
                    package: "swift-argument-parser"
                )
            ]
        ),
        .testTarget(
            name: "SlimLumaKitTests",
            dependencies: ["SlimLumaKit"]
        ),
        .testTarget(
            name: "SlimLumaAppTests",
            dependencies: ["SlimLuma"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
