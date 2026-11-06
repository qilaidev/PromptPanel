// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "PromptPanel",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", "7.0.0"..<"7.9.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "1.10.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.1"),
    ],
    targets: [
        .executableTarget(
            name: "PromptPanel",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/PromptPanel",
            exclude: [
                "Resources/Assets.xcassets",
                "Resources/Info.plist",
                "Resources/PromptPanel.entitlements",
                "Resources/AppIcon.icns",
            ]
        ),
        .testTarget(
            name: "PromptPanelTests",
            dependencies: [
                "PromptPanel",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Tests/PromptPanelTests"
        ),
    ]
)
