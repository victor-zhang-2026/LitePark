// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChatGPTLaterQueue",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ChatGPTLaterQueue", targets: ["ChatGPTLaterQueue"])
    ],
    targets: [
        .executableTarget(name: "ChatGPTLaterQueue")
    ]
)
