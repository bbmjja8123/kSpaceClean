import Foundation

public actor CleanupManager {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public enum CleanupError: Error {
        case fileNotFound(URL)
        case trashFailed(URL, Error)
    }

    /// Moves files to trash. Returns list of successfully trashed files.
    public func moveToTrash(_ items: [FileItem]) async throws -> [CleanupAction] {
        var actions: [CleanupAction] = []
        for item in items {
            guard fileManager.fileExists(atPath: item.url.path) else {
                continue
            }
            do {
                var resultingURL: NSURL?
                try fileManager.trashItem(at: item.url, resultingItemURL: &resultingURL)
                let action = CleanupAction(
                    id: UUID(), file: item, method: .trash,
                    timestamp: Date(), isCompleted: true
                )
                actions.append(action)
            } catch {
                throw CleanupError.trashFailed(item.url, error)
            }
        }
        return actions
    }

    /// Permanently deletes files. Use with caution.
    public func permanentlyDelete(_ items: [FileItem]) async throws -> [CleanupAction] {
        var actions: [CleanupAction] = []
        for item in items {
            guard fileManager.fileExists(atPath: item.url.path) else { continue }
            try fileManager.removeItem(at: item.url)
            let action = CleanupAction(
                id: UUID(), file: item, method: .delete,
                timestamp: Date(), isCompleted: true
            )
            actions.append(action)
        }
        return actions
    }
}
