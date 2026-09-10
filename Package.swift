// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EasySpeech",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "EasySpeech",
            path: "Sources/EasySpeech",
            swiftSettings: [
                .unsafeFlags(["-O", "-whole-module-optimization"], .when(configuration: .release))
            ]
        )
    ]
)
