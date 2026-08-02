import Foundation

/// Facade over `VaultManager` for the cleanup UI. All cleanup now goes through
/// the Trash + Vault dual-write; permanent delete is no longer offered.
public actor CleanupManager {
    private let vault: VaultManager

    public init(vault: VaultManager = VaultManager()) {
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
