// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "kFoundation",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "FileScanner", targets: ["FileScanner"]),
        .library(name: "PrivacyShield", targets: ["PrivacyShield"]),
        .library(name: "AppCatalog", targets: ["AppCatalog"]),
        .library(name: "Capabilities", targets: ["Capabilities"]),
        .library(name: "CommonUtils", targets: ["CommonUtils"]),
        .library(name: "DaemonBridge", targets: ["DaemonBridge"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
        .target(name: "FileScanner", dependencies: ["CommonUtils"]),
        .target(name: "PrivacyShield"),
        .target(name: "AppCatalog"),
        .target(name: "Capabilities"),
        .target(name: "CommonUtils"),
        .target(name: "DaemonBridge"),
        .testTarget(name: "FileScannerTests", dependencies: ["FileScanner"]),
        .testTarget(name: "CommonUtilsTests", dependencies: ["CommonUtils"]),
    ]
)
