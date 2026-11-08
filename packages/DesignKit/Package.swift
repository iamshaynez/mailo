// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DesignKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "DesignKit", targets: ["DesignKit"])],
    dependencies: [
        .package(path: "../CoreKit"),
        .package(path: "../MailProtoKit"),
        .package(path: "../MirrorKit"),
        .package(path: "../AuthKit"),
    ],
    targets: [
        .target(name: "DesignKit", dependencies: [
            "CoreKit",
            "MailProtoKit",
            .product(name: "MirrorKit", package: "MirrorKit"),
            .product(name: "AuthKit", package: "AuthKit"),
        ], resources: [
            // 多语言（DESIGN-003）：开发语言 en；zh-Hans 为第一翻译语言
            .process("Resources"),
        ]),
        .testTarget(name: "DesignKitTests", dependencies: [
            "DesignKit",
            "CoreKit",
            .product(name: "MirrorKit", package: "MirrorKit"),
            .product(name: "AuthKit", package: "AuthKit"),
        ]),
    ]
)
