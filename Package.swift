// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cots",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cots", targets: ["cots"]),
        .executable(name: "CotsApp", targets: ["CotsApp"]),
        .library(name: "CotsCore", targets: ["CotsCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // Shared by every app: notes, format, storage and agent plumbing. Builds on macOS,
        // Linux and Windows.
        .target(name: "CotsCore", dependencies: ["Yams"], path: "core/CotsCore"),
        .executableTarget(
            name: "cots",
            dependencies: ["CotsCore", .product(name: "ArgumentParser", package: "swift-argument-parser")],
            path: "cli"
        ),
        .target(name: "CotsIntegrations", dependencies: ["CotsCore"], path: "core/CotsIntegrations"),
        // The macOS menu bar app. The Windows app lives in apps/windows (Tauri) and only
        // shares the notes format and the `cots` CLI.
        .executableTarget(name: "CotsApp", dependencies: ["CotsCore", "CotsIntegrations"], path: "apps/macos/Sources"),
        .testTarget(name: "CotsCoreTests", dependencies: ["CotsCore"], path: "core/Tests/CotsCoreTests"),
        .testTarget(name: "CotsIntegrationsTests", dependencies: ["CotsIntegrations"], path: "core/Tests/CotsIntegrationsTests"),
    ],
    swiftLanguageModes: [.v6]
)
