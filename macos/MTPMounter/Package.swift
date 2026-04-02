// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MTPMounter",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "mtp-mounter", targets: ["MTPMounter"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.62.0"),
    ],
    targets: [
        .executableTarget(
            name: "MTPMounter",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        )
    ]
)
