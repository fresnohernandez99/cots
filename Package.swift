// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cots",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "cots", targets: ["cots"]),
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
            dependencies: ["CotsCore", "CotsIntegrations", .product(name: "ArgumentParser", package: "swift-argument-parser")],
            path: "cli"
        ),
        .target(name: "CotsIntegrations", dependencies: ["CotsCore"], path: "core/CotsIntegrations"),
        .testTarget(name: "CotsCoreTests", dependencies: ["CotsCore"], path: "core/Tests/CotsCoreTests"),
        .testTarget(name: "CotsIntegrationsTests", dependencies: ["CotsIntegrations"], path: "core/Tests/CotsIntegrationsTests"),
    ],
    swiftLanguageModes: [.v6]
)

// The macOS menu bar app (AppKit, SwiftUI) only exists on macOS. The Windows app lives in
// apps/windows (Tauri) and shares the notes format and the `cots` CLI.
#if os(macOS)
package.products.append(.executable(name: "CotsApp", targets: ["CotsApp"]))
package.targets.append(
    .executableTarget(name: "CotsApp", dependencies: ["CotsCore", "CotsIntegrations"], path: "apps/macos/Sources")
)
#endif
