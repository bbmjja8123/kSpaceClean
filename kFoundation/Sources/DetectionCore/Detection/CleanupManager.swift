import Foundation

/// Facade over `VaultManager` for the cleanup UI. All cleanup now goes through
/// the Trash + Vault dual-write; permanent delete is no longer offered.
public actor CleanupManager {
    private let vault: VaultManager

    public init(vault: VaultManager) {
        self.vault = vault
    }

    public func moveToTrash(_ items: [FileItem], profileType: String = "") async throws -> VaultMoveResult {
        try await vault.moveToTrash(items, profileType: profileType)
    }

    public func restore(vaultItemIds: [UUID]) async throws -> [VaultItem] {
        var restored: [VaultItem] = []
        for id in vaultItemIds {
            restored.append(try await vault.restore(itemID: id))
        }
        return restored
    }

    /// Restores every item of a cleanup session back to its original
    /// location — the "Undo" affordance. Best-effort per file: a file
    /// whose original path is now occupied (or which vanished from the
    /// vault) is reported as a failure instead of aborting the batch.
    @discardableResult
    public func restoreSession(_ session: CleanupSession) async -> [VaultMoveFailure] {
        let items = (try? await vault.vaultItems()) ?? []
        let urlById = Dictionary(
            items
                .filter { session.vaultItemIds.contains($0.id) }
                .map { (id: $0.id, url: $0.originalURL) },
            uniquingKeysWith: { _, url in url }
        )
        var failures: [VaultMoveFailure] = []
        for id in session.vaultItemIds {
            let originalURL = urlById[id] ?? URL(fileURLWithPath: "/")
            do {
                _ = try await vault.restore(itemID: id)
            } catch VaultError.restoreTargetExists(let target) {
                failures.append(VaultMoveFailure(
                    url: target,
                    reason: NSLocalizedString(
                        "A file already exists at the original location",
                        comment: "Undo failure when the restore target is occupied"
                    )
                ))
            } catch {
                failures.append(VaultMoveFailure(url: originalURL, reason: error.localizedDescription))
            }
        }
        return failures
    }

    public func vaultItems() async throws -> [VaultItem] {
        try await vault.vaultItems()
    }

    public func vaultSize() async throws -> Int64 {
        try await vault.vaultSize()
    }

    public func deleteExpired() async throws -> Int {
        try await vault.deleteExpired()
    }
}
