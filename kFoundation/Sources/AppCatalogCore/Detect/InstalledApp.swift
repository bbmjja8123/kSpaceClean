import Foundation
import AppKit

// MARK: - App Source

/// Where an installed app came from.
///
/// Determined by ``AppCatalogService/classifySource(url:bundleID:)``. The source
/// drives uninstall eligibility (system apps are protected) and residue strategy
/// (Homebrew casks and Setapp apps are managed by their own package manager).
public enum AppSource: String, Codable, CaseIterable, Sendable {
    /// Shipped inside `/System/*` — protected, never uninstallable.
    case system
    /// `com.apple.*` bundle ID but living outside `/System`.
    case appleBuiltIn
    /// Mac App Store install, proven by a `Contents/_MASReceipt/receipt`.
    case mas
    /// Developer ID / direct download installed under `/Applications/*`.
    case userInstalled
    /// Installed through a Setapp subscription bundle (`/Applications/Setapp/*`).
    case setapp
    /// Installed by a Homebrew cask (`/opt/homebrew/Caskroom/*` or `/usr/local/Caskroom/*`).
    case homebrew
    /// Origin could not be determined.
    case unknown
}

// MARK: - Residue Type

public enum ResidueType: String, Codable, CaseIterable, Sendable {
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
    /// User-level application log directory (e.g. `~/Library/Logs/<App>/`).
    case log
    /// HTTP cookie storage (e.g. `~/Library/Cookies/<bundleID>.binarycookies`).
    case cookie
    /// AppleScript automation folder (e.g. `~/Library/Application Scripts/<bundleID>/`).
    case appleScript
    case other
}

// MARK: - Residue Risk Level

/// Risk classification that drives the 4-level uninstall confirm sheet
/// (see `kFresh/Features/Detail/UninstallConfirmSheet.swift`).
///
/// The four buckets follow the Kraftly CLAUDE.md §8.6 convention also used
/// by kSpaceClean: 🟢 Recommended (safe by default), ⚪ Optional (off by
/// default, single confirm), 🟠 Caution (off by default, warning copy),
/// 🔴 Dangerous (off by default, double-confirm + literal "DELETE" input).
public enum ResidueRiskLevel: String, Codable, CaseIterable, Sendable {
    case recommended
    case optional
    case caution
    case dangerous

    /// Default checkbox state when the confirm sheet first opens.
    public var defaultSelected: Bool {
        switch self {
        case .recommended: return true
        case .optional, .caution, .dangerous: return false
        }
    }

    /// Human-readable section title shown above the residue list.
    public var sectionTitle: String {
        switch self {
        case .recommended: return "推荐清理"
        case .optional:    return "可选清理"
        case .caution:     return "谨慎清理"
        case .dangerous:   return "高危清理"
        }
    }

    /// Map a ``ResidueType`` (and whether the file lives at system scope) to
    /// its risk bucket. Mirrors CLAUDE.md §8.6 and the spec at
    /// `docs/superpowers/specs/2026-08-03-kfresh-v1x-design.md` §2.1.
    ///
    /// Why this lives here rather than in the detector: the detector only
    /// decides *which* residues to surface; this function decides *how
    /// dangerous* each surfaced residue is, which is independent of the
    /// detection path. Keeping it on the enum means callers (detector,
    /// TrashMover, UninstallConfirmSheet, tests) all reach one mapping.
    public static func classify(type: ResidueType, isSystemLevel: Bool) -> ResidueRiskLevel {
        switch type {
        // 🟢 Cache-like: safe to delete, default ON
        case .caches, .httpStorage, .webKit, .log:
            return .recommended
        // 🔴 Anything that auto-runs on next login or boot
        case .launchAgent, .launchDaemon, .startupItem:
            return .dangerous
        // 🟠 User preferences + auth-bearing cookies
        case .preferences, .cookie:
            return .caution
        // ⚪ Application data — useful to keep, free to wipe
        case .appSupport, .container, .savedState, .groupContainer,
             .plugin, .prefPane, .appleScript, .other:
            return .optional
        }
    }
}

// MARK: - Residue File

public struct ResidueFile: Identifiable, Codable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let type: ResidueType
    public let sizeBytes: Int64
    public let confidence: Double        // 0.0 ~ 1.0
    public let description: String
    public let isSystemLevel: Bool
    public let isProtected: Bool
    public let riskLevel: ResidueRiskLevel

    public init(url: URL,
                type: ResidueType,
                sizeBytes: Int64,
                confidence: Double,
                description: String = "",
                isSystemLevel: Bool = false,
                isProtected: Bool = false,
                riskLevel: ResidueRiskLevel? = nil) {
        self.url = url
        self.type = type
        self.sizeBytes = sizeBytes
        self.confidence = confidence
        self.description = description
        self.isSystemLevel = isSystemLevel
        self.isProtected = isProtected
        self.riskLevel = riskLevel ?? ResidueRiskLevel.classify(type: type, isSystemLevel: isSystemLevel)
    }

    public var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

// MARK: - Startup Item

public enum StartupItemType: String, Codable, CaseIterable {
    case loginItem
    case launchAgent
    case launchDaemon
    case prefPane
}

public struct StartupItem: Identifiable, Codable, Sendable {
    public var id: String { url.path }
    public let name: String
    public let type: StartupItemType
    public let url: URL
    public let appURL: URL?
    public let enabled: Bool
    public let isProtected: Bool

    public init(name: String, type: StartupItemType, url: URL,
                appURL: URL? = nil, enabled: Bool, isProtected: Bool) {
        self.name = name
        self.type = type
        self.url = url
        self.appURL = appURL
        self.enabled = enabled
        self.isProtected = isProtected
    }
}

// MARK: - Installed App

public struct InstalledApp: Identifiable, Hashable, @unchecked Sendable {
    public var id: String { bundleID }
    public let url: URL
    public let displayName: String
    public let bundleID: String
    public let version: String
    public let icon: NSImage
    public let sizeBytes: Int64
    public let source: AppSource
    public let isRunning: Bool
    public let lastUsedDate: Date?
    /// When the app bundle was created on disk, read from its
    /// `FileAttributeKey.creationDate`. Populated by ``AppCatalogService``
    /// from `FileManager` attributes; `nil` when the creation date cannot be
    /// read (missing bundle, sandbox denial, filesystem glitch). Drives the
    /// "最近安装" category filter and the "安装时间" sort option — the two
    /// surfaces that let users reason about freshly installed apps.
    public let installDate: Date?
    public var residues: [ResidueFile] = []

    public init(url: URL, displayName: String, bundleID: String, version: String, icon: NSImage = NSImage(), sizeBytes: Int64 = 0, source: AppSource = .unknown, isRunning: Bool = false, lastUsedDate: Date? = nil, installDate: Date? = nil, residues: [ResidueFile] = []) {
        self.url = url
        self.displayName = displayName
        self.bundleID = bundleID
        self.version = version
        self.icon = icon
        self.sizeBytes = sizeBytes
        self.source = source
        self.isRunning = isRunning
        self.lastUsedDate = lastUsedDate
        self.installDate = installDate
        self.residues = residues
    }

    public var isProtected: Bool {
        Self.isBundleIDProtected(bundleID) || url.path.hasPrefix("/System/")
    }

    public var protectionReason: String? {
        isProtected ? "系统组件不可卸载" : nil
    }

    public var sizeFormatted: String {
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
    public func hash(into hasher: inout Hasher) { hasher.combine(bundleID) }
    public static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.bundleID == rhs.bundleID }
}
