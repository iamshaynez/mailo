// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MirrorKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MirrorKit", targets: ["MirrorKit"])],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
    ],
    targets: [
        .target(name: "MirrorKit", dependencies: [
            "CoreKit",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .testTarget(name: "MirrorKitTests", dependencies: ["MirrorKit", "CoreKit"]),
    ]
)
