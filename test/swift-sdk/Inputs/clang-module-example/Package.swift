// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "ClangModuleExample",
    targets: [
        .executableTarget(name: "Main", dependencies: ["_CModule"]),
        .target(name: "_CModule"),
    ]
)
