// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwapTab",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "SwapTab",
            targets: ["SwapTab"]
        )
    ],
    dependencies: [
        .package(name: "Primitives", path: "../../Packages/Primitives"),
        .package(name: "Style", path: "../../Packages/Style"),
        .package(name: "Components", path: "../../Packages/Components"),
        .package(name: "Store", path: "../../Packages/Store"),
        .package(name: "Swap", path: "../../Features/Swap"),
        .package(name: "PrimitivesComponents", path: "../../Packages/PrimitivesComponents"),
        .package(name: "Assets", path: "../../Packages/Assets")
    ],
    targets: [
        .target(
            name: "SwapTab",
            dependencies: [
                .product(name: "Primitives", package: "Primitives"),
                .product(name: "Style", package: "Style"),
                .product(name: "Components", package: "Components"),
                .product(name: "Store", package: "Store"),
                .product(name: "Swap", package: "Swap"),
                .product(name: "PrimitivesComponents", package: "PrimitivesComponents"),
                .product(name: "Assets", package: "Assets")
            ],
            path: "Sources"
        )
    ]
)
