import Foundation
import AppKit

// MARK: - App Source

enum AppSource: String, Codable, CaseIterable {
    case system          // /System/* — protected
    case appleBuiltIn    // com.apple.* but not in /System
    case mas             // App Store with receipt
    case userInstalled   // /Applications/*
    case unknown
}

// MARK: - Residue Type

enum ResidueType: String, Codable, CaseIterable {
    case preferences
    case caches
    case appSupport = "appSupport"
    case container
    case savedState = "savedState"
    case webKit = "webKit"
    case httpStorage = "httpStorage"
    case groupContainer = "groupContainer"
    case plugin
    case launchAgent
    case launchDaemon
    case prefPane
    case startupItem
    case other
}

// MARK: - Residue File

struct ResidueFile: Identifiable, Codable, @unchecked Sendable {
    var id: String { url.path }
    let url: URL
    let type: ResidueType
    let sizeBytes: Int64
    let confidence: Double        // 0.0 ~ 1.0
    let description: String
    let isSystemLevel: Bool
    let isProtected: Bool

    init(url: URL, type: ResidueType, sizeBytes: Int64, confidence: Double, description: String = "", isSystemLevel: Bool = false, isProtected: Bool = false) {
        self.url = url
        self.type = type
        self.sizeBytes = sizeBytes
        self.confidence = confidence
        self.description = description
        self.isSystemLevel = isSystemLevel
        self.isProtected = isProtected
    }

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

// MARK: - Startup Item

enum StartupItemType: String, Codable, CaseIterable {
    case loginItem
    case launchAgent
    case launchDaemon
    case prefPane
}

struct StartupItem: Identifiable, Codable, Sendable {
    var id: String { url.path }
    let name: String
    let type: StartupItemType
    let url: URL
    let appURL: URL?
    let enabled: Bool
    let isProtected: Bool
}

// MARK: - Installed App

struct InstalledApp: Identifiable, Hashable, @unchecked Sendable {
    var id: String { bundleID }
    let url: URL
    let displayName: String
    let bundleID: String
    let version: String
    let icon: NSImage
    let sizeBytes: Int64
    let source: AppSource
    let isRunning: Bool
    let lastUsedDate: Date?
    var residues: [ResidueFile] = []

    init(url: URL, displayName: String, bundleID: String, version: String, icon: NSImage = NSImage(), sizeBytes: Int64 = 0, source: AppSource = .unknown, isRunning: Bool = false, lastUsedDate: Date? = nil, residues: [ResidueFile] = []) {
        self.url = url
        self.displayName = displayName
        self.bundleID = bundleID
        self.version = version
        self.icon = icon
        self.sizeBytes = sizeBytes
        self.source = source
        self.isRunning = isRunning
        self.lastUsedDate = lastUsedDate
        self.residues = residues
    }

    var isProtected: Bool {
        Self.isBundleIDProtected(bundleID) || url.path.hasPrefix("/System/")
    }

    var protectionReason: String? {
        isProtected ? "系统组件不可卸载" : nil
    }

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    static func isBundleIDProtected(_ bundleID: String) -> Bool {
        let protected: Set<String> = [
            "com.apple.finder",
            "com.apple.Terminal",
            "com.apple.systempreferences",
            "com.apple.dock",
            "com.apple.loginwindow",
            "com.apple.WindowManager",
        ]
        if protected.contains(bundleID) { return true }
        if bundleID.hasPrefix("com.apple.CoreServices.") { return true }
        if bundleID.hasPrefix("com.apple.launchd.") { return true }
        return false
    }

    // MARK: Hashable
    func hash(into hasher: inout Hasher) { hasher.combine(bundleID) }
    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.bundleID == rhs.bundleID }
}
