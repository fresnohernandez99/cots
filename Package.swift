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
        .target(name: "CotsCore", dependencies: ["Yams"]),
        .executableTarget(
            name: "cots",
            dependencies: ["CotsCore", .product(name: "ArgumentParser", package: "swift-argument-parser")],
            path: "Sources/CLI"
        ),
        .target(name: "CotsIntegrations", dependencies: ["CotsCore"]),
        .executableTarget(name: "CotsApp", dependencies: ["CotsCore", "CotsIntegrations"], path: "Sources/App"),
        .testTarget(name: "CotsCoreTests", dependencies: ["CotsCore"]),
        .testTarget(name: "CotsIntegrationsTests", dependencies: ["CotsIntegrations"]),
    ],
    swiftLanguageModes: [.v5]
)
