// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MailProtoKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MailProtoKit", targets: ["MailProtoKit"])],
    dependencies: [
        .package(path: "../CoreKit"),
    ],
    targets: [
        .target(name: "MailProtoKit", dependencies: ["CoreKit"]),
        .testTarget(name: "MailProtoKitTests", dependencies: ["MailProtoKit", "CoreKit"]),
    ]
)
