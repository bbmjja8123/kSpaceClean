import Foundation
@testable import kSift

/// In-memory mock of `VaultRepositoryProtocol` for unit tests. Records every
/// upsert, delete, and session-save so assertions can verify the
/// `VaultManager` calls them in the expected order with the expected rows.
final class MockVaultRepository: VaultRepositoryProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _items: [VaultItem] = []
    private var _sessions: [CleanupSession] = []

    var items: [VaultItem] {
        lock.lock(); defer { lock.unlock() }
        return _items
    }
    var sessions: [CleanupSession] {
        lock.lock(); defer { lock.unlock() }
        return _sessions
    }

    func loadVaultItems() async throws -> [VaultItem] {
        lock.lock(); defer { lock.unlock() }
        return _items
    }

    func upsertVaultItems(_ items: [VaultItem]) async throws {
        lock.lock(); defer { lock.unlock() }
        for item in items {
            _items.removeAll { $0.id == item.id }
            _items.append(item)
        }
    }

    func deleteVaultItems(ids: [UUID]) async throws {
        lock.lock(); defer { lock.unlock() }
        _items.removeAll { ids.contains($0.id) }
    }

    func loadCleanupSessions() async throws -> [CleanupSession] {
        lock.lock(); defer { lock.unlock() }
        return _sessions
    }

    func saveCleanupSession(_ session: CleanupSession) async throws {
        lock.lock(); defer { lock.unlock() }
        _sessions.append(session)
    }
}