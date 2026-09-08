// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "kFoundation",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "kFoundation", targets: ["DesignSystem", "FileScanner", "Capabilities", "CommonUtils", "MetricsKit", "PowerScope"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "FileScanner", targets: ["FileScanner"]),
        .library(name: "Capabilities", targets: ["Capabilities"]),
        .library(name: "CommonUtils", targets: ["CommonUtils"]),
        .library(name: "MetricsKit", targets: ["MetricsKit"]),
        .library(name: "PowerScope", targets: ["PowerScope"]),
        // v2.2 framework architecture — per-app engine modules (kSift / kFresh / kMonitor).
        .library(name: "DetectionCore", targets: ["DetectionCore"]),
        .library(name: "AppCatalogCore", targets: ["AppCatalogCore"]),
        .library(name: "MonitorCore", targets: ["MonitorCore"]),
    ],
    targets: [
        .target(name: "DesignSystem", dependencies: ["MetricsKit"]),
        .target(name: "FileScanner", dependencies: ["CommonUtils"]),
        .target(name: "Capabilities"),
        .target(name: "CommonUtils"),
        .target(name: "MetricsKit"),
        .target(name: "PowerScope"),
        // DetectionCore (extracted from kSift): duplicate/large-file detection
        // pipeline. Depends only on FileScanner — no AppKit/CoreData/Photos.
        .target(name: "DetectionCore", dependencies: ["FileScanner"]),
        // AppCatalogCore (extracted from kFresh): app catalog + residue rules
        // (cask_rules.json / zh_app_mappings.json shipped as package resources).
        .target(
            name: "AppCatalogCore",
            dependencies: ["CommonUtils", "FileScanner"],
            resources: [
                .copy("Resources/cask_rules.json"),
                .copy("Resources/zh_app_mappings.json"),
            ]
        ),
        // MonitorCore (extracted from kMonitor): snapshot export, history/alert
        // repositories, diagnostics. Built on MetricsKit.
        .target(name: "MonitorCore", dependencies: ["MetricsKit"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "FileScannerTests", dependencies: ["FileScanner"]),
        .testTarget(name: "CommonUtilsTests", dependencies: ["CommonUtils", "DesignSystem"]),
        .testTarget(name: "MetricsKitTests", dependencies: ["MetricsKit"]),
        .testTarget(name: "PowerScopeTests", dependencies: ["PowerScope"]),
        .testTarget(name: "DetectionCoreTests", dependencies: ["DetectionCore"]),
        .testTarget(name: "AppCatalogCoreTests", dependencies: ["AppCatalogCore"]),
        .testTarget(name: "MonitorCoreTests", dependencies: ["MonitorCore"]),
    ]
)
