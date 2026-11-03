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
        .executableTarget(name: "CotsApp", dependencies: ["CotsCore"], path: "Sources/App"),
        .testTarget(name: "CotsCoreTests", dependencies: ["CotsCore"]),
    ],
    swiftLanguageModes: [.v5]
)
