import Foundation
import UniformTypeIdentifiers
import FileScanner

public protocol FileWalkerProtocol: Sendable {
    func walk(target: ScanTarget, controller: ScanController,
              progress: @escaping @Sendable (FileEnumerator.ScanResult) -> Void) async throws -> [URL]
}

public actor FileWalker: FileWalkerProtocol {
    private let fileEnumerator: FileEnumerator

    public init(fileEnumerator: FileEnumerator = FileEnumerator()) {
        self.fileEnumerator = fileEnumerator
    }

    public func walk(target: ScanTarget, controller: ScanController,
                     progress: @escaping @Sendable (FileEnumerator.ScanResult) -> Void) async throws -> [URL] {
        let collector = FileCollector()
        let directories = target.directories.map { ($0 as NSString).expandingTildeInPath }

        for dir in directories {
            // Honor pause at the top of each root directory. Enumeration
            // itself doesn't have a safe checkpoint mid-directory, so we
            // suspend before opening it; the user can resume and we'll
            // pick up at this same loop iteration.
            await controller.awaitResumed()
            guard !controller.isCancelled else { return collector.files }
            let url = URL(fileURLWithPath: dir)
            try await fileEnumerator.enumerate(
                root: url,
                progressHandler: { result in
                    guard result.size >= target.minFileSize else { return }
                    // Lemon `listPathContent` 过滤规则（v2.4）：App 包 /
                    // 图库包 / 别名 / 隐藏文件不入组（~home/Pictures 下
                    // 的图库除外——相册库本身是大文件，DaisyDisk 同款
                    // 例外）。缺了这条会扫进 .app 造成误报。
                    if Self.isExcludedKind(result.url) { return }
                    collector.append(result.url)
                    progress(result)
                },
                cancellationToken: controller.fileToken
            )
        }
        return collector.files
    }
}

/// Thread-safe URL collector for use in @Sendable closures.
extension FileWalker {
    /// Lemon-style exclusion: bundles, aliases, hidden files. The
    /// `~/Pictures` library-package exception matches DaisyDisk/Lemon
    /// behavior (a Photos library is a large legit file, not app internals).
    nonisolated static func isExcludedKind(_ url: URL) -> Bool {
        let path = url.path
        // Hidden files (dot-prefix any component after root).
        if url.lastPathComponent.hasPrefix(".") { return true }
        // Package bundles (.app/.photoslibrary/.framework/...), except
        // packages directly under ~/Pictures.
        if url.hasDirectoryPath {
            let home = NSHomeDirectory()
            let inPictures = path.hasPrefix(home + "/Pictures/")
            if !inPictures, url.pathExtension.lowercased() == "app"
                || path.hasSuffix(".photoslibrary")
                || path.hasSuffix(".framework")
                || path.hasSuffix(".bundle")
                || path.hasSuffix(".kext") {
                return true
            }
        }
        // Alias files (Lemon skipped these — a 4KB alias points at the
        // real file which gets scanned on its own).
        if url.pathExtension.lowercased() == "alias" { return true }
        return false
    }
}

private final class FileCollector: @unchecked Sendable {
    private var _files: [URL] = []
    private let lock = NSLock()

    var files: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _files
    }

    func append(_ url: URL) {
        lock.lock()
        _files.append(url)
        lock.unlock()
    }
}
