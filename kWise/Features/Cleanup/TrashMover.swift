import Foundation

public final class TrashMover: Sendable {
    public enum MoveError: Error {
        case trashFailed(URL, Error)
        case snapshotFailed(URL)
        case fileNotFound(URL)
    }

    public init() {}

    public func moveToTrash(urls: [URL]) async -> TrashResult {
        var snapshots: [TrashSnapshot] = []
        var failed: [(URL, MoveError)] = []

        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                failed.append((url, .fileNotFound(url)))
                continue
            }

            do {
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)

                guard let trashURL = trashedURL as? URL,
                      let snapshot = try? await createSnapshot(for: url, trashURL: trashURL) else {
                    failed.append((url, .snapshotFailed(url)))
                    continue
                }

                snapshots.append(snapshot)
            } catch {
                failed.append((url, .trashFailed(url, error)))
            }
        }

        return TrashResult(snapshots: snapshots, failed: failed)
    }

    private func createSnapshot(for url: URL, trashURL: URL) async -> TrashSnapshot? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return nil
        }
        return TrashSnapshot(
            originalPath: url.path,
            trashPath: trashURL.path,
            fileSize: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? Date()
        )
    }
}

public struct TrashResult: Sendable {
    public let snapshots: [TrashSnapshot]
    public let failed: [(URL, TrashMover.MoveError)]

    public var succeeded: [URL] { snapshots.map(\.originalPath).map { URL(fileURLWithPath: $0) } }
}

public struct TrashSnapshot: Codable, Sendable {
    public let originalPath: String
    public let trashPath: String
    public let fileSize: Int64
    public let modifiedAt: Date
}

public extension FileManager {
    var trashDirectory: URL? {
        urls(for: .trashDirectory, in: .userDomainMask).first
    }
}

public extension TrashMover {
    /// Best-effort snapshot helper — nil-safe for use inside concurrent Tasks.
    ///
    /// Captures the file size + modification date at the moment of the move so
    /// the history row has accurate provenance even if the file is later
    /// mutated in Trash (Finder renames on conflict, etc.).
    func snapshotIfPossible(original: URL, trashURL: URL) async -> TrashSnapshot? {
        guard let values = try? original.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return nil
        }
        return TrashSnapshot(
            originalPath: original.path,
            trashPath: trashURL.path,
            fileSize: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? Date()
        )
    }
}
