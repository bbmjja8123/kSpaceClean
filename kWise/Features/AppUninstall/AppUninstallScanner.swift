import Foundation
import AppKit
import CommonUtils
import AppCatalogCore

// MARK: - Data Model

public struct UninstallAppEntry: Identifiable, Sendable {
    public let id = UUID()
    public let appName: String
    public let bundleID: String
    public let appURL: URL
    public let appSize: Int64
    public var leftoverURLs: [URL]
    public var leftoverSize: Int64
    public var isSelected: Bool = true
    /// 孤儿残留（App 本体已不存在）— 默认不选，确认后才清理。
    public var isOrphan: Bool
    public var totalSize: Int64 { appSize + leftoverSize }

    public init(appName: String, bundleID: String, appURL: URL,
                appSize: Int64, leftoverURLs: [URL], leftoverSize: Int64,
                isSelected: Bool = true, isOrphan: Bool = false,
                lastUsedDate: Date?, installDate: Date?, isRunning: Bool,
                source: AppSource, residues: [ResidueFile]) {
        self.appName = appName
        self.bundleID = bundleID
        self.appURL = appURL
        self.appSize = appSize
        self.leftoverURLs = leftoverURLs
        self.leftoverSize = leftoverSize
        self.isSelected = isSelected
        self.isOrphan = isOrphan
        self.lastUsedDate = lastUsedDate
        self.installDate = installDate
        self.isRunning = isRunning
        self.source = source
        self.residues = residues
    }
    // v2.3 Phase 4 — computed once at scan time (never in the render path).
    public let lastUsedDate: Date?
    public let installDate: Date?
    public let isRunning: Bool
    public let source: AppSource
    /// Residue files with risk classification, for the tiered confirm sheet.
    public let residues: [ResidueFile]
}

// MARK: - Scanner (AppCatalogCore adapter)

/// App-uninstall scanner backed by the AppCatalogCore engine (kFresh's
/// `AppCatalogService` four-source catalog + `ResidueDetector`'s 14 residue
/// template families with confidence scoring).
///
/// The old in-app implementation used an 11-template path match against a
/// hand-rolled `/Applications` walk; the engine swap adds the 1141-rule
/// cask rule store, zh-Hans display-name mappings, Homebrew Caskroom and
/// Setapp sources, and MAS-receipt source classification (which degrades
/// gracefully under the App Sandbox).
///
/// Uninstallation itself stays on kWise's `CleanupEngine` (trash → restorable
/// 30-day history → quota metering); kFresh's TrashMover is deliberately
/// NOT adopted (it is Core-Data bound and assumes /Applications write
/// access a MAS app cannot have).
public final class AppUninstallScanner: @unchecked Sendable {

    private let catalog = AppCatalogService()
    private let residueDetector: ResidueDetector

    public init() {
        // Production initializer: loads the 1141-rule cask_rules.json from
        // the AppCatalogCore package bundle (Bundle.module).
        self.residueDetector = ResidueDetector(ruleStore: BundleRuleStore.loadFromBundledJSON())
    }

    // MARK: Public API

    /// Scans installed apps via the catalog engine and locates their
    /// leftover files via the residue engine. Sorted total-size descending.
    public func scan() async -> [UninstallAppEntry] {
        let apps = await catalog.scan()

        var entries: [UninstallAppEntry] = []
        for app in apps where app.source != .system && app.source != .appleBuiltIn {
            guard app.sizeBytes > 0 else { continue }
            let residues = await residueDetector.detectResidues(
                bundleID: app.bundleID,
                appName: app.displayName,
                appURL: app.url
            )
            // Keep only residues that actually exist and are NOT the app
            // bundle itself; skip protected system locations.
            let leftovers = residues
                .filter { !$0.isProtected && !$0.isSystemLevel }
                .map(\.url)
                .filter { FileManager.default.fileExists(atPath: $0.path) }

            entries.append(UninstallAppEntry(
                appName: app.displayName,
                bundleID: app.bundleID,
                appURL: app.url,
                appSize: app.sizeBytes,
                leftoverURLs: leftovers,
                leftoverSize: leftovers.reduce(0) { $0 + Self.sizeOf($1) },
                lastUsedDate: app.lastUsedDate,
                installDate: app.installDate,
                isRunning: app.isRunning,
                source: app.source,
                residues: residues
            ))
        }
        return entries.sorted { $0.totalSize > $1.totalSize }
    }

    /// 孤儿残留扫描 (v2.4)：App 已被手动删除但残留还在。返回按 App 分组
    /// 的条目（isSelected 默认 false — 用户确认后才清理，谨慎对待）。
    public func scanOrphans() async -> [UninstallAppEntry] {
        let orphans = await residueDetector.detectOrphans(apps: await catalog.scan())
        return orphans.map { app, residues in
            let urls = residues.map(\.url).filter {
                FileManager.default.fileExists(atPath: $0.path)
            }
            return UninstallAppEntry(
                appName: app.displayName,
                bundleID: app.bundleID,
                appURL: app.url,
                appSize: 0,
                leftoverURLs: urls,
                leftoverSize: urls.reduce(0) { $0 + Self.sizeOf($1) },
                isOrphan: true,
                lastUsedDate: nil, installDate: nil, isRunning: false,
                source: .unknown, residues: residues
            )
        }
        .sorted { $0.leftoverSize > $1.leftoverSize }
    }

    /// 拖入 .app 即扫 (v2.6)：为拖入的 App 构建完整条目（含残留与
    /// 使用信息），高置信度残留预选。
    public func scanDraggedApp(at appURL: URL) async -> UninstallAppEntry? {
        guard appURL.pathExtension.lowercased() == "app" else { return nil }
        let bundle = Bundle(url: appURL)
        let bundleID = bundle?.bundleIdentifier
            ?? "unknown.\(appURL.deletingPathExtension().lastPathComponent)"
        let appName = appURL.deletingPathExtension().lastPathComponent
        let residues = await residueDetector.detectResidues(
            bundleID: bundleID, appName: appName, appURL: appURL
        )
        let usable = residues.filter { !$0.isProtected && !$0.isSystemLevel }
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
        let installDate = (try? appURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate
        return UninstallAppEntry(
            appName: appName,
            bundleID: bundleID,
            appURL: appURL,
            appSize: Self.sizeOf(appURL),
            leftoverURLs: usable.map(\.url),
            leftoverSize: usable.reduce(0) { $0 + Self.sizeOf($1.url) },
            isSelected: true,
            isOrphan: false,
            lastUsedDate: AppCatalogService.lastUsedDate(at: appURL),
            installDate: installDate,
            isRunning: false,
            source: .userInstalled,
            residues: residues
        )
    }

    /// App Reset (v2.6, CMM 功能)：保留 App 本体，只清偏好与缓存类残留
    /// （Preferences/Caches/HTTPStorage/Saved State），Logs/Cookies 等
    /// 含用户数据的不动。
    public func reset(entry: UninstallAppEntry) async throws {
        let resettableTypes: Set<ResidueType> = [.preferences, .caches, .httpStorage, .savedState]
        let resetURLs = entry.residues
            .filter { resettableTypes.contains($0.type) && !$0.isProtected }
            .map(\.url)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !resetURLs.isEmpty else { return }
        for url in resetURLs {
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        }
    }

    /// Moves the app bundle and all associated leftover files to the Trash
    /// via the shared engine path (the view model routes through
    /// `CleanupEngine.cleanup(targets:)` — this direct API remains for
    /// tests only).
    public func uninstall(entry: UninstallAppEntry) async throws {
        let allURLs = [entry.appURL] + entry.leftoverURLs
        var errors: [URL: Error] = [:]

        for url in allURLs {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            } catch {
                errors[url] = error
            }
        }

        if !errors.isEmpty {
            throw TrashError.failedItems(errors)
        }
    }

    /// Recursive size of a file or directory (leftover sizing).
    static func sizeOf(_ url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? url.resourceValues(forKeys: [.fileSizeKey])).flatMap { $0.fileSize.map(Int64.init) } ?? 0
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }
}

// MARK: - Errors

public enum TrashError: LocalizedError {
    case failedItems([URL: Error])

    public var errorDescription: String? {
        switch self {
        case .failedItems(let dict):
            let count = dict.count
            return "\(count) item(s) could not be moved to Trash."
        }
    }
}
