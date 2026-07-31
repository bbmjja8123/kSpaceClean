// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "kFoundation",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "kFoundation", targets: ["DesignSystem", "FileScanner", "Capabilities", "CommonUtils", "MetricsKit"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "FileScanner", targets: ["FileScanner"]),
        .library(name: "Capabilities", targets: ["Capabilities"]),
        .library(name: "CommonUtils", targets: ["CommonUtils"]),
        .library(name: "MetricsKit", targets: ["MetricsKit"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
        .target(name: "FileScanner", dependencies: ["CommonUtils"]),
        .target(name: "Capabilities"),
        .target(name: "CommonUtils"),
        .target(name: "MetricsKit"),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "FileScannerTests", dependencies: ["FileScanner"]),
        .testTarget(name: "CommonUtilsTests", dependencies: ["CommonUtils", "DesignSystem"]),
        .testTarget(name: "MetricsKitTests", dependencies: ["MetricsKit"]),
    ]
)