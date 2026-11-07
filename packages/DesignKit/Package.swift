// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DesignKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "DesignKit", targets: ["DesignKit"])],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../MailProtoKit"),
        .package(path: "../MirrorKit"),
    ],
    targets: [
        .target(name: "DesignKit", dependencies: [
            "CoreKit",
            "MailProtoKit",
            .product(name: "MirrorKit", package: "MirrorKit"),
        ]),
        .testTarget(name: "DesignKitTests", dependencies: [
            "DesignKit",
            "CoreKit",
            .product(name: "MirrorKit", package: "MirrorKit"),
        ]),
    ]
)
