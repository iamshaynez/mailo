// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AuthKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "AuthKit", targets: ["AuthKit"])],
    dependencies: [
        .package(path: "../CoreKit"),
    ],
    targets: [
        .target(name: "AuthKit", dependencies: ["CoreKit"]),
        .testTarget(name: "AuthKitTests", dependencies: ["AuthKit", "CoreKit"]),
    ]
)
