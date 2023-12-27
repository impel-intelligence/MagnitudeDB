// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MagnitudeDB",
    platforms: [
        .iOS(.v13),
        .macOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MagnitudeDB",
            targets: ["MagnitudeDB"]),
    ], 
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.1"),
        .package(url: "https://github.com/ActuallyTaylor/SLlama", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MagnitudeDB", dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ]),
        .testTarget(
            name: "MagnitudeDBTests",
            dependencies: ["MagnitudeDB", "SLlama"]),
    ]
)
