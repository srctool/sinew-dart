// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "sinew_security",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "sinew-security", targets: ["sinew_security"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "sinew_security",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
