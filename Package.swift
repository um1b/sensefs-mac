// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SenseFS",
    platforms: [.macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "SenseFS",
            targets: ["SenseFS"]
        ),
    ],
    dependencies: [
        // ZIPFoundation for extracting Office document files
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        // Swift Transformers for tokenization and HuggingFace Hub
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "0.1.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SenseFS",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "Transformers", package: "swift-transformers")
            ],
            path: "SenseFS"
        ),
    ]
)
