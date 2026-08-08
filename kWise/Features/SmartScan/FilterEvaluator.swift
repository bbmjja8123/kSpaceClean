import Foundation
import CoreData
import FileScanner

// MARK: - Batch Buffer

/// 线程安全的批量写入缓冲区，每 100 条自动写入 Core Data。
/// 使用 background context 支持并发 scan engine 安全写入。
final class BatchBuffer: @unchecked Sendable {
    private var entries: [ScanResultEntry] = []
    private var totalSize: Int64 = 0
    private let lock = NSLock()
    private let backgroundContext: NSManagedObjectContext

    init(backgroundContext: NSManagedObjectContext) {
        self.backgroundContext = backgroundContext
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return entries.count
    }

    var totalBytes: Int64 {
        lock.lock(); defer { lock.unlock() }
        return totalSize
    }

    func append(_ entry: ScanResultEntry) {
        lock.lock()
        entries.append(entry)
        totalSize += entry.size
        let shouldFlush = entries.count >= 100
        lock.unlock()

        if shouldFlush { flush() }
    }

    /// 在 background context 上同步写入；调用方保证不在 main actor 上调用。
    func flush() {
        lock.lock()
        let batch = entries
        entries = []
        entries.reserveCapacity(100)
        let batchSize = totalSize
        totalSize = 0
        lock.unlock()

        guard !batch.isEmpty else { return }

        let ctx = backgroundContext
        ctx.performAndWait {
            for entry in batch {
                let fe = FileEntry(context: ctx)
                fe.id = UUID()
                fe.path = entry.path
                fe.size = entry.size
                fe.category = entry.category
                fe.confidence = 0.5
                fe.subCategoryID = Int64(entry.subCategoryID)
                fe.actionID = Int64(entry.actionID ?? -1)
                fe.isRecommended = entry.isRecommended
            }
            do {
                try ctx.save()
            } catch {
                print("[BatchBuffer] save error: \(error)")
            }
        }

        // Drop the notification on the main queue so consumers can update UI safely.
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .init("ScanBatchFlushed"),
                object: nil,
                userInfo: ["files": batch.count, "bytes": batchSize]
            )
        }
    }
}

// MARK: - FilterEvaluator

/// 过滤规则评估器 — 路径解析、FilterExpression 评估、带层级和过滤的文件枚举
public final class FilterEvaluator: @unchecked Sendable {
    private let filters: [Int: FilterRule]
    private let fileManager: FileManager

    // .app bundle ID 缓存
    private var bundleIDCache: [String: String?] = [:]
    private let cacheLock = NSLock()

    public init(filters: [Int: FilterRule] = ScanRuleSet.default.filters) {
        self.filters = filters
        self.fileManager = FileManager.default
    }

    // MARK: - 路径解析

    /// 解析 ScanPath 为具体的文件 URL 列表
    public func resolvePath(_ scanPath: ScanPath) -> [URL] {
        switch scanPath.type {
        case .absolute:
            return resolveAbsolutePath(scanPath.value)
        case .tempDir:
            return [URL(fileURLWithPath: NSTemporaryDirectory())]
        case .fireFoxProfiles:
            return resolveFireFoxProfiles()
        case .searchName, .searchBundle:
            return resolveSearchPath(scanPath)
        }
    }

    private func resolveAbsolutePath(_ value: String) -> [URL] {
        let expanded = (value as NSString).expandingTildeInPath
        // 检查路径中是否包含正则表达式段（如 ~/Library/Containers/(.+)/Data/Library/Caches）
        if value.contains("(") || value.contains(")") || value.contains("+") {
            return resolveRegexPath(value)
        }
        return [URL(fileURLWithPath: expanded)]
    }

    /// 处理包含正则段的路径（例如 Containers/(.+)/Data/Library/Caches）
    private func resolveRegexPath(_ value: String) -> [URL] {
        let expanded = (value as NSString).expandingTildeInPath
        let comps = (expanded as NSString).pathComponents

        // 找到第一个存在的前缀路径（正则段之前的部分）
        var basePath = ""
        var regexStarted = false
        for comp in comps {
            if comp.range(of: "[.+*?^$()|\\[\\]{}]", options: .regularExpression) != nil {
                regexStarted = true
                break
            }
            basePath = (basePath as NSString).appendingPathComponent(comp)
        }

        guard regexStarted, fileManager.fileExists(atPath: basePath) else {
            return [URL(fileURLWithPath: expanded)]
        }

        // 用正则匹配枚举目录
        let baseURL = URL(fileURLWithPath: basePath)
        let regexPart = String(expanded.dropFirst(basePath.count))
        let regexComps = (regexPart as NSString).pathComponents.filter { $0 != "/" }

        var resolved: [URL] = []

        func walk(_ current: URL, remaining: ArraySlice<String>) {
            guard let segment = remaining.first else {
                resolved.append(current)
                return
            }
            let rest = remaining.dropFirst()

            if segment.range(of: "[.+*?^$()|\\[\\]{}]", options: .regularExpression) != nil {
                guard let items = try? fileManager.contentsOfDirectory(
                    at: current, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
                ) else { return }
                for item in items {
                    if item.lastPathComponent.range(of: segment, options: .regularExpression) != nil {
                        let next = rest.isEmpty ? item : item.appendingPathComponent(rest.joined(separator: "/"))
                        resolved.append(next)
                    }
                }
            } else {
                walk(current.appendingPathComponent(segment), remaining: rest)
            }
        }

        walk(baseURL, remaining: ArraySlice(regexComps))
        return resolved.isEmpty ? [URL(fileURLWithPath: expanded)] : resolved
    }

    /// 解析 Firefox 用户配置文件目录（profiles.ini）
    private func resolveFireFoxProfiles() -> [URL] {
        let iniPath = NSHomeDirectory() + "/Library/Application Support/Firefox/profiles.ini"
        guard fileManager.fileExists(atPath: iniPath),
              let content = try? String(contentsOfFile: iniPath, encoding: .utf8) else {
            return []
        }

        var profiles: [URL] = []
        let lines = content.components(separatedBy: .newlines)
        var currentPath: String?
        var isRelative = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Path=") {
                currentPath = String(trimmed.dropFirst(5))
            } else if trimmed.hasPrefix("IsRelative=") {
                isRelative = trimmed == "IsRelative=1"
                if let path = currentPath {
                    let fullPath = isRelative
                        ? NSHomeDirectory() + "/Library/Application Support/Firefox/" + path
                        : path
                    if fileManager.fileExists(atPath: fullPath) {
                        profiles.append(URL(fileURLWithPath: fullPath))
                    }
                    currentPath = nil
                }
            }
        }

        // 兼容末尾没有 IsRelative 的格式
        if let path = currentPath {
            let fullPath = NSHomeDirectory() + "/Library/Application Support/Firefox/" + path
            if fileManager.fileExists(atPath: fullPath) {
                profiles.append(URL(fileURLWithPath: fullPath))
            }
        }

        return profiles
    }

    /// 解析 searchName / searchBundle 路径（枚举基目录下的子项）
    private func resolveSearchPath(_ scanPath: ScanPath) -> [URL] {
        let expanded = (scanPath.value as NSString).expandingTildeInPath
        guard let items = try? fileManager.contentsOfDirectory(atPath: expanded) else {
            return []
        }
        let base = URL(fileURLWithPath: expanded)
        return items.map { base.appendingPathComponent($0) }
    }

    // MARK: - 已安装应用快照（用于残留检测）

    public struct InstalledAppInfo: Sendable {
        public let name: String
        public let bundleID: String
        public let path: String
    }

    public func scanInstalledApps() -> [InstalledAppInfo] {
        let appDirs = ["/Applications", NSHomeDirectory() + "/Applications"]
        var apps: [InstalledAppInfo] = []

        for dir in appDirs {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let fullPath = "\(dir)/\(item)"
                let bundle = Bundle(path: fullPath)
                apps.append(InstalledAppInfo(
                    name: (item as NSString).deletingPathExtension,
                    bundleID: bundle?.bundleIdentifier ?? "",
                    path: fullPath
                ))
            }
        }

        return apps
    }

    // MARK: - 过滤器评估

    /// 评估 FilterExpression 是否匹配给定的文件
    /// - Returns: true = 文件通过过滤器（应该包含），false = 被过滤掉
    public func evaluate(_ expression: FilterExpression, for url: URL, fileSize: Int64, fileTime: Date?) -> Bool {
        switch expression {
        case .filterID(let id):
            guard let rule = filters[id] else { return true }
            return evaluateRule(rule, for: url, fileSize: fileSize, fileTime: fileTime)
        case .and(let children):
            return children.allSatisfy { evaluate($0, for: url, fileSize: fileSize, fileTime: fileTime) }
        case .or(let children):
            return children.contains { evaluate($0, for: url, fileSize: fileSize, fileTime: fileTime) }
        }
    }

    private func evaluateRule(_ rule: FilterRule, for url: URL, fileSize: Int64, fileTime: Date?) -> Bool {
        let matched: Bool

        switch rule.column {
        case .filename:
            matched = matchString(url.lastPathComponent, relation: rule.relation, pattern: rule.value)

        case .filepath:
            matched = matchString(url.path, relation: rule.relation, pattern: rule.value)

        case .filesize:
            let threshold = Int64(rule.value) ?? 0
            switch rule.relation {
            case .greater: matched = fileSize > threshold
            case .smaller: matched = fileSize < threshold
            default:       matched = fileSize == threshold
            }

        case .time:
            guard let fileTime else { matched = false; break }
            let thresholdSeconds = TimeInterval(rule.value) ?? 0
            let age = Date().timeIntervalSince(fileTime)
            switch rule.relation {
            case .greater: matched = age > thresholdSeconds
            case .smaller: matched = age < thresholdSeconds
            default:       matched = age == thresholdSeconds
            }

        case .bundleid:
            let bid = bundleIdentifier(for: url)
            matched = matchString(bid ?? "", relation: rule.relation, pattern: rule.value)

        case .subfilecount:
            let count = (try? fileManager.contentsOfDirectory(atPath: url.path).count) ?? 0
            let threshold = Int(rule.value) ?? 0
            switch rule.relation {
            case .greater: matched = count > threshold
            case .smaller: matched = count < threshold
            default:       matched = count == threshold
            }

        case .subfilepath:
            let expanded = (rule.value as NSString).expandingTildeInPath
            matched = fileManager.fileExists(atPath: expanded)

        case .app:
            let isSigned = checkCodeSigned(url)
            let expectSigned = rule.value.lowercased() == "signed"
            matched = isSigned == expectSigned

        case .languageKey:
            let lang = extractLanguageKey(from: url)
            matched = matchString(lang ?? "", relation: rule.relation, pattern: rule.value)
        }

        return rule.action == .include ? matched : !matched
    }

    private func matchString(_ value: String, relation: FilterRule.Relation, pattern: String) -> Bool {
        switch relation {
        case .is:        return value == pattern
        case .beginsWith: return value.hasPrefix(pattern)
        case .endsWith:  return value.hasSuffix(pattern)
        case .contains:  return value.contains(pattern)
        case .matches:   return value.range(of: pattern, options: .regularExpression) != nil
        case .greater:   return false
        case .smaller:   return false
        }
    }

    // MARK: - Bundle ID 缓存

    private func bundleIdentifier(for url: URL) -> String? {
        guard let appURL = findAppBundle(url) else { return nil }

        cacheLock.lock()
        if let cached = bundleIDCache[appURL.path] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let bundle = Bundle(path: appURL.path)
        let bid = bundle?.bundleIdentifier

        cacheLock.lock()
        bundleIDCache[appURL.path] = bid
        cacheLock.unlock()

        return bid
    }

    private func findAppBundle(_ url: URL) -> URL? {
        var current = url
        while current.path != "/" {
            if current.pathExtension == "app" {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    private func checkCodeSigned(_ url: URL) -> Bool {
        // 检查是否包含代码签名目录
        let sigPath = url.appendingPathComponent("Contents/_CodeSignature")
        return fileManager.fileExists(atPath: sigPath.path)
    }

    private func extractLanguageKey(from url: URL) -> String? {
        let path = url.path
        guard let range = path.range(of: "/([^/]+)\\.lproj/", options: .regularExpression) else { return nil }
        return path[range]
            .replacingOccurrences(of: "\\.lproj/", with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - 文件枚举

    /// 枚举路径下的文件，应用扫描过滤器
    /// - Parameters:
    ///   - level: 0=单文件, 1=直接子项, -1=递归全部, N=N层深度
    ///   - filenamePattern: 可选文件名正则过滤
    ///   - scanFilters: 扫描级过滤器（路径排除）
    ///   - cleanHiddenFiles: 是否清理隐藏文件
    ///   - onFile: 每个通过过滤的文件的回调
    public func enumerateFiles(
        at rootURL: URL,
        level: Int,
        filenamePattern: String?,
        scanFilters: FilterExpression?,
        cleanHiddenFiles: Bool,
        speed: ScanSpeed,
        cancellationToken: CancellationToken?,
        onFile: @Sendable (URL, Int64) -> Void
    ) async throws {
        guard fileManager.fileExists(atPath: rootURL.path) else { return }

        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDir) else { return }

        // Level 0: 单文件模式
        if level == 0 {
            guard !isDir.boolValue else { return }
            try enumerateSingleFile(rootURL, filenamePattern: filenamePattern, scanFilters: scanFilters, onFile: onFile)
            return
        }

        // Level 1: 直接子项
        if level == 1 {
            try await enumerateDirectChildren(
                rootURL, filenamePattern: filenamePattern, scanFilters: scanFilters,
                cleanHiddenFiles: cleanHiddenFiles, speed: speed, cancellationToken: cancellationToken, onFile: onFile
            )
            return
        }

        // Level -1 或 N > 1: 递归遍历（有限深度）
        try await enumerateRecursive(
            rootURL, level: level, filenamePattern: filenamePattern, scanFilters: scanFilters,
            cleanHiddenFiles: cleanHiddenFiles, speed: speed, cancellationToken: cancellationToken, onFile: onFile
        )
    }

    private func enumerateSingleFile(
        _ url: URL,
        filenamePattern: String?,
        scanFilters: FilterExpression?,
        onFile: @Sendable (URL, Int64) -> Void
    ) throws {
        if let pattern = filenamePattern {
            guard url.lastPathComponent.range(of: pattern, options: .regularExpression) != nil else { return }
        }

        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        let size = attrs?[.size] as? Int64 ?? 0

        if let filters = scanFilters {
            let modDate = attrs?[.modificationDate] as? Date
            guard evaluate(filters, for: url, fileSize: size, fileTime: modDate) else { return }
        }

        onFile(url, size)
    }

    private func enumerateDirectChildren(
        _ url: URL,
        filenamePattern: String?,
        scanFilters: FilterExpression?,
        cleanHiddenFiles: Bool,
        speed: ScanSpeed,
        cancellationToken: CancellationToken?,
        onFile: @Sendable (URL, Int64) -> Void
    ) async throws {
        let opts: FileManager.DirectoryEnumerationOptions = cleanHiddenFiles ? [.skipsHiddenFiles] : []
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .contentModificationDateKey], options: opts
        ) else { return }

        var fileCount = 0
        for fileURL in contents {
            try Task.checkCancellation()
            if cancellationToken?.isCancelled == true { return }

            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]),
                  !(values.isDirectory ?? false) else { continue }

            if let pattern = filenamePattern {
                guard fileURL.lastPathComponent.range(of: pattern, options: .regularExpression) != nil else { continue }
            }

            let size = Int64(values.fileSize ?? 0)
            let modDate = values.contentModificationDate

            if let filters = scanFilters {
                guard evaluate(filters, for: fileURL, fileSize: size, fileTime: modDate) else { continue }
            }

            onFile(fileURL, size)

            fileCount += 1
            try await throttle(fileCount, speed: speed)
        }
    }

    private func enumerateRecursive(
        _ url: URL,
        level: Int,
        filenamePattern: String?,
        scanFilters: FilterExpression?,
        cleanHiddenFiles: Bool,
        speed: ScanSpeed,
        cancellationToken: CancellationToken?,
        onFile: @Sendable (URL, Int64) -> Void
    ) async throws {
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey, .isPackageKey, .contentModificationDateKey]
        let opts: FileManager.DirectoryEnumerationOptions = cleanHiddenFiles
            ? [.skipsHiddenFiles, .skipsPackageDescendants]
            : [.skipsPackageDescendants]

        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: opts) else { return }

        var fileCount = 0
        while let fileURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            if cancellationToken?.isCancelled == true { return }

            // 层级限制（enumerator.level 是 NSDirectoryEnumerator 的深度属性）
            if level > 1, enumerator.level > level { continue }

            guard let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]),
                  !(values.isDirectory ?? false) else { continue }

            if let pattern = filenamePattern {
                guard fileURL.lastPathComponent.range(of: pattern, options: .regularExpression) != nil else { continue }
            }

            let size = Int64(values.fileSize ?? 0)
            let modDate = values.contentModificationDate

            if let filters = scanFilters {
                guard evaluate(filters, for: fileURL, fileSize: size, fileTime: modDate) else { continue }
            }

            onFile(fileURL, size)

            fileCount += 1
            try await throttle(fileCount, speed: speed)
        }
    }

    private func throttle(_ count: Int, speed: ScanSpeed) async throws {
        guard speed.batchSize > 0, count % speed.batchSize == 0 else { return }
        try await Task.yield()
        if speed.sleepNanoseconds > 0 {
            try await Task.sleep(nanoseconds: speed.sleepNanoseconds)
        }
    }
}
