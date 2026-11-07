// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MlKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MlKit", targets: ["MlKit"])],
    dependencies: [
        .package(path: "../CoreKit"),
    ],
    targets: [
        .target(name: "MlKit", dependencies: ["CoreKit"]),
        .testTarget(name: "MlKitTests", dependencies: ["MlKit", "CoreKit"]),
    ]
)
