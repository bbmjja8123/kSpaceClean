import Foundation
import AppKit
import FileScanner

// MARK: - Specialized Scanner Protocol

/// 专用扫描器协议 — 每种 ScanActionType 的具体扫描实现。
/// 通过 ScanEngine 注册表分发，避免在主循环中堆叠 if/else。
public protocol SpecializedScanner: Sendable {
    var actionType: ScanActionType { get }
    func scan(url: URL, level: Int, speed: ScanSpeed,
              cancellationToken: CancellationToken,
              onFile: @Sendable (URL, Int64) -> Void) async throws
}

// MARK: - Utility

/// 计算目录递归总大小（仅枚举一次，stat 缓存由 URL 完成）。
@inlinable
func directoryRecursiveSize(_ url: URL) -> Int64 {
    guard let enumerator = FileManager.default.enumerator(at: url,
                                                          includingPropertiesForKeys: [.fileSizeKey],
                                                          options: [.skipsHiddenFiles]) else {
        return 0
    }
    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
        if let values = try? fileURL.resourceValues(forKeys: Set([.fileSizeKey])),
           let size = values.fileSize {
            total += Int64(size)
        }
    }
    return total
}

/// 检测文件是否被 NSWorkspace 识别为仍在运行的应用所使用。
/// 仅在 cleanup 阶段使用，不在扫描路径中使用。
@inlinable
func isBundleInUse(_ url: URL) -> Bool {
    let path = url.path
    for app in NSWorkspace.shared.runningApplications {
        guard let appURL = app.bundleURL else { continue }
        if path.hasPrefix(appURL.path) || path == appURL.path {
            return true
        }
    }
    return false
}

// MARK: - WeChat Image Scanner

/// 微信聊天图片 — 仅保留超过 90 天的图片以避免误删近期聊天内容。
public final class WeChatImageScanner: SpecializedScanner {
    public let actionType: ScanActionType = .wechatImage
    private let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic", "bmp", "tiff"
    ]
    private let ninetyDaysAgo: TimeInterval = -90 * 86400

    public init() {}

    public func scan(url: URL, level: Int, speed: ScanSpeed,
                     cancellationToken: CancellationToken,
                     onFile: @Sendable (URL, Int64) -> Void) async throws {
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        let cutoff = Date().addingTimeInterval(ninetyDaysAgo)
        for case let fileURL as URL in enumerator {
            if cancellationToken.isCancelled { return }
            guard let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                  values.isRegularFile == true else { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }
            if let modDate = values.contentModificationDate, modDate > cutoff {
                continue
            }
            let size = Int64(values.fileSize ?? 0)
            onFile(fileURL, size)
        }
    }
}

// MARK: - WeChat File Scanner

/// 微信聊天文档 — pdf/doc/xls/ppt/txt 等。无需 90 天过滤。
public final class WeChatFileScanner: SpecializedScanner {
    public let actionType: ScanActionType = .wechatFile
    private let docExtensions: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf"
    ]

    public init() {}

    public func scan(url: URL, level: Int, speed: ScanSpeed,
                     cancellationToken: CancellationToken,
                     onFile: @Sendable (URL, Int64) -> Void) async throws {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        for case let fileURL as URL in enumerator {
            if cancellationToken.isCancelled { return }
            guard let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                  values.isRegularFile == true else { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard docExtensions.contains(ext) else { continue }
            let size = Int64(values.fileSize ?? 0)
            onFile(fileURL, size)
        }
    }
}

// MARK: - WeChat Video Scanner

/// 微信聊天视频 — 默认仅保留 90 天之前的视频。
public final class WeChatVideoScanner: SpecializedScanner {
    public let actionType: ScanActionType = .wechatVideo
    private let videoExtensions: Set<String> = [
        "mp4", "mov", "avi", "mkv", "wmv", "flv", "m4v"
    ]
    private let ninetyDaysAgo: TimeInterval = -90 * 86400

    public init() {}

    public func scan(url: URL, level: Int, speed: ScanSpeed,
                     cancellationToken: CancellationToken,
                     onFile: @Sendable (URL, Int64) -> Void) async throws {
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        let cutoff = Date().addingTimeInterval(ninetyDaysAgo)
        for case let fileURL as URL in enumerator {
            if cancellationToken.isCancelled { return }
            guard let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                  values.isRegularFile == true else { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard videoExtensions.contains(ext) else { continue }
            if let modDate = values.contentModificationDate, modDate > cutoff {
                continue
            }
            let size = Int64(values.fileSize ?? 0)
            onFile(fileURL, size)
        }
    }
}

// MARK: - WeChat Audio Scanner

/// 微信语音消息 — silk/amr/mp3 等。
public final class WeChatAudioScanner: SpecializedScanner {
    public let actionType: ScanActionType = .wechatAudio
    private let audioExtensions: Set<String> = [
        "mp3", "aac", "wav", "silk", "ogg", "m4a", "amr"
    ]

    public init() {}

    public func scan(url: URL, level: Int, speed: ScanSpeed,
                     cancellationToken: CancellationToken,
                     onFile: @Sendable (URL, Int64) -> Void) async throws {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        for case let fileURL as URL in enumerator {
            if cancellationToken.isCancelled { return }
            guard let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                  values.isRegularFile == true else { continue }
            let ext = fileURL.pathExtension.lowercased()
            guard audioExtensions.contains(ext) else { continue }
            let size = Int64(values.fileSize ?? 0)
            onFile(fileURL, size)
        }
    }
}

// MARK: - Derived App Scanner

/// Xcode DerivedData .app — 扫描 DerivedData/<project>/Build/Products/<config>/<name>.app，
/// 报告整个 .app bundle 的总大小（一次枚举求和）。
public final class DerivedAppScanner: SpecializedScanner {
    public let actionType: ScanActionType = .derivedApp

    public init() {}

    public func scan(url: URL, level: Int, speed: ScanSpeed,
                     cancellationToken: CancellationToken,
                     onFile: @Sendable (URL, Int64) -> Void) async throws {
        let projectDirs = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []

        for projectDir in projectDirs {
            if cancellationToken.isCancelled { return }
            let productsDir = projectDir.appendingPathComponent("Build/Products")
            guard FileManager.default.fileExists(atPath: productsDir.path) else { continue }
            let configs = (try? FileManager.default.contentsOfDirectory(
                at: productsDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )) ?? []
            for configDir in configs {
                if cancellationToken.isCancelled { return }
                let apps = (try? FileManager.default.contentsOfDirectory(
                    at: configDir,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )) ?? []
                for product in apps where product.pathExtension == "app" {
                    if cancellationToken.isCancelled { return }
                    let total = directoryRecursiveSize(product)
                    onFile(product, total)
                }
            }
        }
    }
}

// MARK: - Broken Plist Scanner

/// 损坏的 plist 配置文件 — 尝试 PropertyListSerialization 解析，失败的视为损坏。
public final class BrokenPlistScanner: SpecializedScanner {
    public let actionType: ScanActionType = .brokenPlist

    public init() {}

    public func scan(url: URL, level: Int, speed: ScanSpeed,
                     cancellationToken: CancellationToken,
                     onFile: @Sendable (URL, Int64) -> Void) async throws {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        for case let fileURL as URL in enumerator {
            if cancellationToken.isCancelled { return }
            guard let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                  values.isRegularFile == true else { continue }
            guard fileURL.pathExtension.lowercased() == "plist" else { continue }

            if let data = try? Data(contentsOf: fileURL) {
                do {
                    _ = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                    continue  // 解析成功 — 不是损坏的 plist
                } catch {
                    let size = Int64(values.fileSize ?? 0)
                    onFile(fileURL, size)
                }
            }
        }
    }
}

// MARK: - Broken Register Scanner

/// 损坏的 Launch Agent/Daemon plist 注册项 — ProgramArguments 中引用的可执行文件已不存在。
public final class BrokenRegisterScanner: SpecializedScanner {
    public let actionType: ScanActionType = .brokenRegister

    public init() {}

    public func scan(url: URL, level: Int, speed: ScanSpeed,
                     cancellationToken: CancellationToken,
                     onFile: @Sendable (URL, Int64) -> Void) async throws {
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        for case let fileURL as URL in enumerator {
            if cancellationToken.isCancelled { return }
            guard let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                  values.isRegularFile == true else { continue }
            guard fileURL.pathExtension.lowercased() == "plist" else { continue }

            guard let data = try? Data(contentsOf: fileURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                    as? [String: Any] else { continue }

            // ProgramArguments (array of strings) or Program (string)
            let candidatePaths: [String]
            if let programArgs = plist["ProgramArguments"] as? [String] {
                candidatePaths = programArgs
            } else if let program = plist["Program"] as? String {
                candidatePaths = [program]
            } else {
                continue
            }

            let fm = FileManager.default
            let hasMissing = candidatePaths.contains { path in
                !fm.fileExists(atPath: path)
            }
            if hasMissing {
                let size = Int64(values.fileSize ?? 0)
                onFile(fileURL, size)
            }
        }
    }
}

// MARK: - Scanner Registry

/// 内置专用扫描器注册表 — 在 ScanEngine 中按 ScanActionType 索引。
public enum SpecializedScannerRegistry {
    public static let defaults: [ScanActionType: SpecializedScanner] = [
        .wechatImage:    WeChatImageScanner(),
        .wechatFile:     WeChatFileScanner(),
        .wechatVideo:    WeChatVideoScanner(),
        .wechatAudio:    WeChatAudioScanner(),
        .derivedApp:     DerivedAppScanner(),
        .brokenPlist:    BrokenPlistScanner(),
        .brokenRegister: BrokenRegisterScanner(),
    ]
}
