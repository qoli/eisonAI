// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "EisonAIKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "EisonAIKit", targets: ["EisonAIKit"])
    ],
    dependencies: [
        .package(path: "../../AnyLanguageModel", traits: ["MLX"]),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
    ],
    targets: [
        .target(
            name: "EisonAIKit",
            dependencies: [
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ]
        )
    ]
)
