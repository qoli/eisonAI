// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "MLXDownloadProbe",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "mlx-download-probe", targets: ["MLXDownloadProbe"])
    ],
    dependencies: [
        .package(path: "../../../swift-transformers")
    ],
    targets: [
        .executableTarget(
            name: "MLXDownloadProbe",
            dependencies: [
                .product(name: "Hub", package: "swift-transformers")
            ]
        )
    ]
)
