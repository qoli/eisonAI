// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "EisonAIExtensionModelKit",
    platforms: [
        .iOS(.v17),
        .macCatalyst(.v17),
    ],
    products: [
        .library(
            name: "EisonAIExtensionModelKit",
            targets: ["EisonAIExtensionModelKit"]
        )
    ],
    dependencies: [
        .package(path: "../../../AnyLanguageModel")
    ],
    targets: [
        .target(
            name: "EisonAIExtensionModelKit",
            dependencies: [
                .product(name: "AnyLanguageModel", package: "AnyLanguageModel")
            ]
        )
    ]
)
