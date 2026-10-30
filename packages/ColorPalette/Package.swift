// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ColorPalette",
    platforms: [.macOS(.v12)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "ColorPalette",
            targets: ["ColorPalette"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(name: "Colors", path: "../Colors"),
        .package(name: "ApiCredentials", path: "../ApiCredentials"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "ColorPalette",
            dependencies: [
                .product(name: "Colors", package: "Colors", condition: nil),
                .product(name: "ApiCredentials", package: "ApiCredentials", condition: nil),
            ]),
        .testTarget(
            name: "ColorPaletteTests",
            dependencies: ["ColorPalette"]),
    ]
)
