// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "ReaderMacNative",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(
            name: "ReaderMacNative",
            targets: ["ReaderMacNative"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .executableTarget(
            name: "ReaderMacNative",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Sources/ReaderMacNative",
            linkerSettings: [
                .linkedFramework("WebKit"),
            ]
        ),
    ]
)
