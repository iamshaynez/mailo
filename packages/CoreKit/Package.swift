// swift-tools-version:5.10
// 注：CLT 27 的 ManifestAPI 缺 6.0 manifest 符号，暂用 5.10；装完整 Xcode 后升回 6.x 并开严格并发（基线 D1）。
import PackageDescription

let package = Package(
    name: "CoreKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"])
    ],
    targets: [
        .target(name: "CoreKit"),
        .testTarget(name: "CoreKitTests", dependencies: ["CoreKit"]),
    ]
)
