// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "EisonAIKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "EisonAIKit", targets: ["EisonAIKit"])
    ],
    dependencies: [
        .package(path: "../../AnyLanguageModel", traits: ["MLX"]),
    ],
    targets: [
        .target(
            name: "EisonAIKit",
            dependencies: [
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
            ]
        )
    ]
)
