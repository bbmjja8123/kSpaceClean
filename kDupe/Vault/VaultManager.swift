import CryptoKit
import Foundation

/// Failures that can abort a vault operation. Copy failures abort the whole
/// batch (originals are never touched); trash failures are surfaced per-file in
/// `VaultMoveResult.failures` instead.
public enum VaultError: Error, Sendable, Equatable {
    /// The vault root could not be created or is unusable.
    case vaultUnavailable(String)
    /// Copying the file into the vault failed (aborts the batch).
    case copyFailed(URL, String)
    /// The copied file's SHA-256 did not match the source (aborts the batch).
    case hashMismatch(URL)
    /// No stored vault item matches the given id.
    case vaultItemNotFound(UUID)
    /// The vault copy is gone from disk (cannot restore).
    case vaultCopyMissing(URL)
    /// The restore target already exists on disk.
    case restoreTargetExists(URL)
    /// Copying the vault copy back to the target failed.
    case restoreFailed(URL, String)
}

/// Owns the private vault: Trash + Vault dual-write, restore, and expiry.
///
/// Guarantee (spec §5): a file is only trashed after a SHA-256-verified copy
/// sits in the vault, so clearing the macOS Trash can never lose a cleaned
/// file within its retention window.
public actor VaultManager {
    private let vaultRoot: URL
    private let repository: any VaultRepositoryProtocol
    private let fileManager: FileManager
    private let hashFile: @Sendable (URL) throws -> String
    private let now: @Sendable () -> Date
    private let uuid: @Sendable () -> UUID

    public init(
        vaultRoot: URL? = nil,
        repository: any VaultRepositoryProtocol = VaultRepositoryCoreData(),
        fileManager: FileManager = .default,
        hashFile: @escaping @Sendable (URL) throws -> String = VaultManager.sha256(of:),
        now: @escaping @Sendable () -> Date = Date.init,
        uuid: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.vaultRoot = vaultRoot ?? Self.defaultVaultRoot()
        self.repository = repository
        self.fileManager = fileManager
        self.hashFile = hashFile
        self.now = now
        self.uuid = uuid
    }

    /// `~/Library/Application Support/kSift/Vault/` (or the temp dir fallback).
    public static func defaultVaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("kSift/Vault", isDirectory: true)
    }

    // MARK: - Move to trash

    /// Dual-writes a batch: copies every file into the vault with SHA-256
    /// verification first, then trashes the originals.
    ///
    /// - If **any** copy/verify fails, the whole batch is aborted: every vault
    ///   copy made so far is removed and no original is trashed.
    /// - Trash failures do not roll back the rest: the file's vault copy is
    ///   removed (the original stays in place) and the failure is reported in
    ///   the result, so the vault keeps a 1:1 invariant — every `VaultItem`
    ///   corresponds to a trashed original.
    public func moveToTrash(
        _ items: [FileItem],
        profileType: String = "",
        retentionDays: Int = 30
    ) async throws -> VaultMoveResult {
        guard !items.isEmpty else {
            return VaultMoveResult(session: nil, items: [], failures: [])
        }

        let sessionId = uuid()
        var vaultItems: [VaultItem] = []
        var failures: [VaultMoveFailure] = []

        // Phase 1 — copy + verify every file into the vault.
        do {
            try fileManager.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        } catch {
            throw VaultError.vaultUnavailable(error.localizedDescription)
        }
        for item in items {
            if !fileManager.fileExists(atPath: item.url.path) {
                failures.append(VaultMoveFailure(url: item.url, reason: "文件不存在，可能已被移动或删除"))
                continue
            }
            let vaultURL = Self.vaultDestination(for: item, root: vaultRoot, uuid: uuid)
            do {
                try fileManager.copyItem(at: item.url, to: vaultURL)
            } catch {
                failures.append(VaultMoveFailure(url: item.url, reason: "复制到保险库失败: \(error.localizedDescription)"))
                continue
            }
            do {
                let expected = try (item.hash ?? hashFile(item.url))
                let actual = try hashFile(vaultURL)
                guard actual == expected else {
                    try? fileManager.removeItem(at: vaultURL)
                    failures.append(VaultMoveFailure(url: item.url, reason: "SHA-256 校验失败，已中止整个批次"))
                    continue
                }
                vaultItems.append(VaultItem(
                    id: uuid(),
                    originalURL: item.url,
                    vaultPath: vaultURL,
                    vaultedAt: now(),
                    expiresAt: now().addingTimeInterval(TimeInterval(retentionDays) * 86_400),
                    originalSize: item.size,
                    sha256: actual,
                    parentSessionId: sessionId,
                    status: .vaulted
                ))
            } catch {
                try? fileManager.removeItem(at: vaultURL)
                failures.append(VaultMoveFailure(url: item.url, reason: "哈希计算失败: \(error.localizedDescription)"))
            }
        }

        // Any copy failure aborts the batch: originals stay, no records written.
        guard failures.isEmpty else {
            for item in vaultItems {
                try? fileManager.removeItem(at: item.vaultPath)
            }
            return VaultMoveResult(session: nil, items: [], failures: failures)
        }

        // Phase 2 — trash the verified copies. Trash failures keep the vault
        // consistent by removing the copy and reporting the failure.
        var trashed: [VaultItem] = []
        for item in vaultItems {
            do {
                try fileManager.trashItem(at: item.originalURL, resultingItemURL: nil)
                trashed.append(item)
            } catch {
                try? fileManager.removeItem(at: item.vaultPath)
                failures.append(VaultMoveFailure(url: item.originalURL, reason: "移入废纸篓失败: \(error.localizedDescription)"))
            }
        }

        guard !trashed.isEmpty else {
            return VaultMoveResult(session: nil, items: [], failures: failures)
        }

        let session = CleanupSession(
            id: sessionId,
            timestamp: now(),
            profileType: profileType,
            totalReclaimable: trashed.reduce(0) { $0 + $1.originalSize },
            vaultItemIds: trashed.map(\.id)
        )
        try await repository.upsertVaultItems(trashed)
        try await repository.saveCleanupSession(session)

        return VaultMoveResult(session: session, items: trashed, failures: failures)
    }

    // MARK: - Restore

    /// Restores a vault item to its original path, or to `targetURL` when given.
    ///
    /// Refuses to overwrite an existing target. On success the vault copy is
    /// physically removed and the item is re-flagged `.restored` with a 7-day
    /// history window.
    public func restore(itemID: UUID, to targetURL: URL? = nil) async throws -> VaultItem {
        let items = try await repository.loadVaultItems()
        guard let item = items.first(where: { $0.id == itemID }) else {
            throw VaultError.vaultItemNotFound(itemID)
        }
        guard fileManager.fileExists(atPath: item.vaultPath.path) else {
            throw VaultError.vaultCopyMissing(item.vaultPath)
        }

        let target = targetURL ?? item.originalURL
        guard !fileManager.fileExists(atPath: target.path) else {
            throw VaultError.restoreTargetExists(target)
        }

        do {
            try fileManager.copyItem(at: item.vaultPath, to: target)
        } catch {
            throw VaultError.restoreFailed(target, error.localizedDescription)
        }
        do {
            let restoredHash = try hashFile(target)
            guard restoredHash == item.sha256 else {
                try? fileManager.removeItem(at: target)
                throw VaultError.hashMismatch(target)
            }
        } catch let error as VaultError {
            throw error
        } catch {
            try? fileManager.removeItem(at: target)
            throw VaultError.restoreFailed(target, error.localizedDescription)
        }

        try? fileManager.removeItem(at: item.vaultPath)

        let updated = VaultItem(
            id: item.id,
            originalURL: item.originalURL,
            vaultPath: item.vaultPath,
            vaultedAt: item.vaultedAt,
            expiresAt: now().addingTimeInterval(7 * 86_400),
            originalSize: item.originalSize,
            sha256: item.sha256,
            parentSessionId: item.parentSessionId,
            status: .restored
        )
        try await repository.upsertVaultItems([updated])
        return updated
    }

    // MARK: - Expiry & inspection

    /// Removes every expired vault item: the physical copy (if any) plus the
    /// stored record. Returns how many items were purged.
    public func deleteExpired(referenceDate: Date? = nil) async throws -> Int {
        let cutoff = referenceDate ?? now()
        let items = try await repository.loadVaultItems()
        let expired = items.filter { $0.expiresAt < cutoff }
        guard !expired.isEmpty else { return 0 }

        for item in expired where item.status == .vaulted {
            try? fileManager.removeItem(at: item.vaultPath)
        }
        try await repository.deleteVaultItems(ids: expired.map(\.id))
        return expired.count
    }

    public func vaultItems() async throws -> [VaultItem] {
        try await repository.loadVaultItems()
    }

    /// Disk footprint of live vault copies (`.restored` items no longer hold a
    /// copy, so they are excluded).
    public func vaultSize() async throws -> Int64 {
        let items = try await repository.loadVaultItems()
        return items.filter { $0.status == .vaulted }.reduce(0) { $0 + $1.originalSize }
    }

    public func cleanupSessions() async throws -> [CleanupSession] {
        try await repository.loadCleanupSessions()
    }

    // MARK: - SHA-256

    /// Streaming SHA-256 of a file's contents in 1 MiB chunks.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hexString(hasher.finalize())
    }

    private static func vaultDestination(for item: FileItem, root: URL, uuid: () -> UUID) -> URL {
        let name = "\(uuid().uuidString)\(item.url.pathExtension.isEmpty ? "" : ".\(item.url.pathExtension)")"
        return root.appendingPathComponent(name)
    }
}

private func hexString(_ digest: SHA256.Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
}
