// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "ImpulseProxy",
    platforms: [.macOS(.v12)],
    products: [
        .library(
            name: "ImpulseProxy",
            targets: ["ImpulseProxy"]),
    ],
    targets: [
        .binaryTarget(
            name: "LibXray",
            url: "https://github.com/XTLS/libXray/releases/download/v26.9.30/libxray-apple-cgo.zip",
            checksum: "91343cd7542f85dffb17c9e273f0afde207b0004aa49848949e69e4c12450f80"),
        .target(
            name: "ImpulseProxy",
            dependencies: ["LibXray"]),
        .testTarget(
            name: "ImpulseProxyTests",
            dependencies: ["ImpulseProxy"]),
    ]
)
