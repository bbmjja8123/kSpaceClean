import Foundation
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
            guard !controller.isCancelled else { return collector.files }
            let url = URL(fileURLWithPath: dir)
            try await fileEnumerator.enumerate(
                root: url,
                progressHandler: { result in
                    guard result.size >= target.minFileSize else { return }
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
