import Foundation

public actor FileEnumerator {
    public struct ScanResult: Sendable {
        public let url: URL
        public let size: Int64
        public let isDirectory: Bool
    }

    public enum ScanError: Error {
        case cancelled
        case permissionDenied(URL)
    }

    public init() {}

    public func enumerate(
        root: URL,
        progressHandler: @Sendable (ScanResult) -> Void,
        cancellationToken: CancellationToken
    ) async throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            if cancellationToken.isCancelled { throw ScanError.cancelled }

            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
                  !(values.isDirectory ?? false) else { continue }

            let result = ScanResult(url: url, size: Int64(values.fileSize ?? 0), isDirectory: false)
            progressHandler(result)
        }
    }
}

public final class CancellationToken: @unchecked Sendable {
    public private(set) var isCancelled = false
    public func cancel() { isCancelled = true }

    public init() {}
}
