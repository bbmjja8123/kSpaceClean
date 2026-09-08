import Foundation

/// Persistence boundary for the private vault. Implementations are expected to
/// be value-faithful: every stored `VaultItem` round-trips to an equal value.
public protocol VaultRepositoryProtocol: Sendable {
    func loadVaultItems() async throws -> [VaultItem]
    func upsertVaultItems(_ items: [VaultItem]) async throws
    func deleteVaultItems(ids: [UUID]) async throws
    func loadCleanupSessions() async throws -> [CleanupSession]
    func saveCleanupSession(_ session: CleanupSession) async throws
}
