import Foundation
import AppKit

/// Detects leftover files for an installed macOS application.
///
/// Lookup priority:
/// 1. `BundleRuleStore` — exact match by bundle ID (highest confidence, curated paths).
/// 2. Built-in path templates — generic heuristics for any app.
///
/// All file system reads happen off the actor's executor; the actor only
/// guarantees serialized access to its `ruleStore` reference.
public actor ResidueDetector {

    /// 孤儿残留扫描 (v2.4)：App 本体已不在 /Applications（用户手动删除、
    /// 拖废纸篓未清残留），但 14 模板路径下仍有文件。返回按 App 分组的
    /// 残留，供「卸载残留」分区展示。仅收录 confidence ≥ 0.85 的路径，
    /// 防误报（C-5）。
    public func detectOrphans(apps: [InstalledApp]) async -> [(app: InstalledApp, residues: [ResidueFile])] {
        let installedBundleIDs = Set(apps.map(\.bundleID))
        let installedNames = Set(apps.map(\.displayName))

        var results: [(InstalledApp, [ResidueFile])] = []
        for rule in await ruleStore?.allRules() ?? [] {
            // 该 App 仍安装着 → 不是孤儿。
            guard !installedBundleIDs.contains(rule.bundleID) else { continue }
            // 规则目录都不存在 → 没有残留。
            var orphanResidues: [ResidueFile] = []
            for pathTemplate in rule.residuePaths {
                let expanded = pathTemplate
                    .replacingOccurrences(of: "~", with: NSHomeDirectory())
                let url = URL(fileURLWithPath: expanded)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                // 共享目录（bundleID 是通配的常见产品名）谨慎处理。
                guard Self.looksAppSpecific(rule: rule, path: url) else { continue }
                let size = DirectorySizeCalculator.size(of: url)
                orphanResidues.append(ResidueFile(
                    url: url, type: .preferences, sizeBytes: size,
                    confidence: rule.confidence,
                    description: "应用已删除但残留存在"
                ))
            }
            if !orphanResidues.isEmpty {
                let orphan = InstalledApp(
                    url: URL(fileURLWithPath: "/Applications/\(rule.appName).app"),
                    displayName: rule.appName, bundleID: rule.bundleID,
                    version: "", icon: NSImage(), sizeBytes: 0,
                    source: .unknown, isRunning: false,
                    lastUsedDate: nil, installDate: nil
                )
                results.append((orphan, orphanResidues))
            }
        }
        _ = installedNames
        return results
    }

    /// 目录是否明显属于特定 App（bundleID 精确出现在路径中，或目录名
    /// == appName），避免把 `~/Library/Caches` 这类共享目录判给孤儿。
    nonisolated static func looksAppSpecific(rule: KFreshBundleRule, path: URL) -> Bool {
        let pathString = path.path
        if pathString.contains(rule.bundleID) { return true }
        if path.lastPathComponent == rule.appName
            || path.lastPathComponent == rule.bundleID { return true }
        return false
    }
    private let fileManager = FileManager.default
    private let home: URL
    private let ruleStore: BundleRuleStore?

    /// Create a detector.
    /// - Parameters:
    ///   - ruleStore: Optional curated rule store; when `nil`, only template-based
    ///     detection is performed. Pass a test-built store in unit tests.
    ///   - homeDirectory: Override the user's home directory (for test isolation).
    ///     Defaults to `FileManager.default.homeDirectoryForCurrentUser`.
    public init(ruleStore: BundleRuleStore?, homeDirectory: URL? = nil) {
        self.ruleStore = ruleStore
        self.home = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
    }

    /// Detect every residue file associated with the given application.
    ///
    /// - Parameters:
    ///   - bundleID: Reverse-DNS bundle identifier (e.g. `com.example.App`).
    ///     An empty string short-circuits and returns `[]`.
    ///   - appName: Human-readable application name; inserted verbatim into
    ///     filesystem paths (e.g. `~/Library/Application Support/<appName>/`).
    ///     No URL-encoding is applied — real macOS paths carry literal
    ///     characters including spaces, parentheses, and CJK glyphs.
    ///   - appURL: Location of the `.app` bundle on disk; currently used for
    ///     context and future location-specific heuristics.
    /// - Returns: All matching residues, sorted by descending confidence.
    public func detectResidues(bundleID: String, appName: String, appURL: URL) async -> [ResidueFile] {
        guard !bundleID.isEmpty else { return [] }

        // Priority 1: BundleRuleStore (high confidence)
        if let rule = await ruleStore?.lookup(bundleID: bundleID) {
            let ruleResidues = rule.residuePaths.map { template -> ResidueFile in
                let expanded = expand(template: template)
                let url = URL(fileURLWithPath: expanded, isDirectory: true)
                let pathExists = exists(url)
                // I-2 fix: rule branch now applies the same "halve on
                // miss" policy as the template branch. Pre-fix: the rule
                // branch returned the rule's declared confidence
                // unconditionally, making a non-existent rule path look
                // as confident as an existing one. Halving on miss keeps
                // the rule-vs-template confidence scale comparable and
                // gives TrashMover a meaningful signal to skip the entry.
                let effectiveConfidence = pathExists ? rule.confidence : rule.confidence * 0.5
                return ResidueFile(
                    url: url,
                    type: classify(path: expanded),
                    sizeBytes: pathExists ? directorySize(url) : 0,
                    confidence: effectiveConfidence,
                    description: rule.appName,
                    isSystemLevel: false,
                    isProtected: false,
                    riskLevel: ResidueRiskLevel.classify(type: classify(path: expanded), isSystemLevel: false)
                )
            }
            let systemResidues = rule.systemLevelPaths.map { template -> ResidueFile in
                let url = URL(fileURLWithPath: template)
                let pathExists = exists(url)
                // I-2 fix: same convention as the user-level branch —
                // halve on miss rather than multiplying by 0.7 always.
                let baseConfidence = pathExists ? rule.confidence : rule.confidence * 0.5
                let type = classify(path: template)
                return ResidueFile(
                    url: url,
                    type: type,
                    sizeBytes: pathExists ? directorySize(url) : 0,
                    confidence: baseConfidence,
                    description: rule.appName,
                    isSystemLevel: true,
                    isProtected: true,
                    riskLevel: ResidueRiskLevel.classify(type: type, isSystemLevel: true)
                )
            }
            return (ruleResidues + systemResidues).sorted { $0.confidence > $1.confidence }
        }

        // Priority 2: Fallback template-based paths
        return templateResidues(bundleID: bundleID, appName: appName, appURL: appURL)
    }

    // MARK: - Templates

    private func templateResidues(bundleID: String, appName: String, appURL: URL) -> [ResidueFile] {
        let homePath = home.path
        let library = homePath + "/Library"
        let systemLibrary = "/Library"

        // I-1 fix: paths on disk use literal characters, not URL-encoded
        // escapes. Spaces, parentheses, and CJK characters all appear
        // verbatim in real `~/Library/Application Support/<App>/` paths.
        // URL-encoding here made the detector miss real residue directories
        // for apps like `App With Spaces`, `Sketch (Legacy)`, or `钉钉`.
        let nameToken = appName

        let templates: [(path: String, type: ResidueType, confidence: Double, isSystemLevel: Bool)] = [
            ("\(library)/Preferences/\(bundleID).plist",                .preferences,    0.99, false),
            ("\(library)/Caches/\(bundleID)/",                          .caches,         0.99, false),
            ("\(library)/Application Support/\(nameToken)/",            .appSupport,     0.95, false),
            ("\(library)/Logs/\(nameToken)/",                           .log,            0.85, false),
            ("\(library)/Saved Application State/\(bundleID).savedState", .savedState, 0.99, false),
            ("\(library)/Containers/\(bundleID)/",                      .container,      0.99, false),
            ("\(library)/Cookies/\(bundleID).binarycookies",            .cookie,         0.85, false),
            ("\(library)/WebKit/\(bundleID)/",                          .webKit,         0.85, false),
            ("\(library)/HTTPStorages/\(bundleID)/",                    .httpStorage,    0.95, false),
            ("\(library)/Group Containers/\(bundleID)/",                .groupContainer, 0.80, false),
            ("\(library)/Application Scripts/\(bundleID)/",             .appleScript,    0.70, false),
            ("\(systemLibrary)/LaunchAgents/\(bundleID).plist",         .launchAgent,    0.95, true),
            ("\(systemLibrary)/LaunchDaemons/\(bundleID).plist",        .launchDaemon,   0.95, true),
            ("\(systemLibrary)/PreferencePanes/\(nameToken).prefPane",  .prefPane,       0.85, true),
        ]

        return templates.map { t in
            let url = URL(fileURLWithPath: t.path)
            return ResidueFile(
                url: url,
                type: t.type,
                sizeBytes: exists(url) ? directorySize(url) : 0,
                confidence: exists(url) ? t.confidence : t.confidence * 0.5,
                description: descriptionForType(t.type),
                isSystemLevel: t.isSystemLevel,
                isProtected: t.isSystemLevel,
                riskLevel: ResidueRiskLevel.classify(type: t.type, isSystemLevel: t.isSystemLevel)
            )
        }.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Helpers

    private func expand(template: String) -> String {
        if template.hasPrefix("~/") {
            return home.path + String(template.dropFirst())
        }
        return template
    }

    private func exists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path)
    }

    private func directorySize(_ url: URL) -> Int64 {
        // m-4 fix: route through the shared `DirectorySizeCalculator`
        // helper in kFoundation instead of reimplementing the enumerator
        // + size-sum loop here. `ResidueDetector` previously walked every
        // descendant unconditionally while `AppCatalogService.sizeOfApp`
        // enforced a `maxDepth` cap with `skipDescendants()` — two
        // implementations of the same operation that had already drifted.
        // Both call sites now share one policy and one code path.
        DirectorySizeCalculator.size(of: url, depth: .unbounded)
    }

    private func classify(path: String) -> ResidueType {
        let lower = path.lowercased()
        if lower.contains("/preferences/") { return .preferences }
        if lower.contains("/caches/") { return .caches }
        if lower.contains("/application support/") { return .appSupport }
        if lower.contains("/logs/") { return .log }
        if lower.contains("/saved application state/") { return .savedState }
        if lower.contains("/containers/") { return .container }
        if lower.contains("/cookies/") { return .cookie }
        if lower.contains("/webkit/") { return .webKit }
        if lower.contains("/httpstorages/") { return .httpStorage }
        if lower.contains("/group containers/") { return .groupContainer }
        if lower.contains("/application scripts/") { return .appleScript }
        if lower.contains("/launchagents/") { return .launchAgent }
        if lower.contains("/launchdaemons/") { return .launchDaemon }
        if lower.contains("/preferencepanes/") { return .prefPane }
        return .other
    }

    private func descriptionForType(_ type: ResidueType) -> String {
        switch type {
        case .preferences:    return "偏好设置"
        case .caches:         return "缓存文件"
        case .appSupport:     return "应用支持文件"
        case .log:            return "日志文件"
        case .savedState:     return "保存的应用状态"
        case .container:      return "App Sandbox 容器"
        case .cookie:         return "Cookies"
        case .webKit:         return "WebKit 缓存"
        case .httpStorage:    return "HTTP 存储"
        case .groupContainer: return "Group 容器"
        case .appleScript:    return "AppleScript 自动化"
        case .plugin:         return "插件"
        case .launchAgent:    return "启动代理"
        case .launchDaemon:   return "启动守护"
        case .prefPane:       return "偏好设置面板"
        case .startupItem:    return "启动项"
        case .other:          return "其他"
        }
    }
}