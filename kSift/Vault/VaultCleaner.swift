import Foundation

/// Maintenance job for the vault: purging expired items.
///
/// The app runs this at launch, once a day (via a background task), and on the
/// History page's "Clear Expired Now" button. It is intentionally thin — all
/// logic lives in `VaultManager`.
public actor VaultCleaner {
    private let vault: VaultManager

    public init(vault: VaultManager = VaultManager()) {
        self.vault = vault
    }

    /// Removes expired vault items; returns how many were purged.
    public func purgeExpired(referenceDate: Date? = nil) async throws -> Int {
        try await vault.deleteExpired(referenceDate: referenceDate)
    }

    /// Summary used by the History page / vault capacity warning.
    public func snapshot() async throws -> VaultSnapshot {
        async let items = vault.vaultItems()
        async let bytes = vault.vaultSize()
        async let sessions = vault.cleanupSessions()
        let (loadedItems, loadedBytes, loadedSessions) = try await (items, bytes, sessions)
        return VaultSnapshot(
            itemCount: loadedItems.count,
            liveBytes: loadedBytes,
            sessionCount: loadedSessions.count
        )
    }
}

public struct VaultSnapshot: Sendable, Equatable {
    public let itemCount: Int
    public let liveBytes: Int64
    public let sessionCount: Int

    public init(itemCount: Int, liveBytes: Int64, sessionCount: Int) {
        self.itemCount = itemCount
        self.liveBytes = liveBytes
        self.sessionCount = sessionCount
    }
}
