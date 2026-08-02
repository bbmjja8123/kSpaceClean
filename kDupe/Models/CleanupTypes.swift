import Foundation

public enum CleanupMethod: String, Sendable, Codable {
    case trash
    case delete
}

public struct CleanupAction: Sendable, Identifiable, Codable {
    public let id: UUID
    public let file: FileItem
    public let method: CleanupMethod
    public let timestamp: Date
    public var isCompleted: Bool

    public init(id: UUID, file: FileItem, method: CleanupMethod, timestamp: Date, isCompleted: Bool = false) {
        self.id = id
        self.file = file
        self.method = method
        self.timestamp = timestamp
        self.isCompleted = isCompleted
    }
}

public struct CleanupRecord: Sendable, Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let actions: [CleanupAction]
    public let totalSpaceReclaimed: Int64

    public init(id: UUID, timestamp: Date, actions: [CleanupAction], totalSpaceReclaimed: Int64) {
        self.id = id
        self.timestamp = timestamp
        self.actions = actions
        self.totalSpaceReclaimed = totalSpaceReclaimed
    }
}

// MARK: - Vault

/// Lifecycle of a file held in the private vault.
public enum VaultItemStatus: String, Sendable, Codable {
    /// The file is in the vault and can be restored.
    case vaulted
    /// The file was restored; the record lingers for 7 days as history.
    case restored
}

/// A single file's entry in the private vault (Trash + Vault dual-write).
public struct VaultItem: Sendable, Identifiable, Codable, Equatable {
    public let id: UUID
    public let originalURL: URL
    public let vaultPath: URL
    public let vaultedAt: Date
    public let expiresAt: Date
    public let originalSize: Int64
    public let sha256: String
    public let parentSessionId: UUID
    public let status: VaultItemStatus

    public init(
        id: UUID,
        originalURL: URL,
        vaultPath: URL,
        vaultedAt: Date,
        expiresAt: Date,
        originalSize: Int64,
        sha256: String,
        parentSessionId: UUID,
        status: VaultItemStatus
    ) {
        self.id = id
        self.originalURL = originalURL
        self.vaultPath = vaultPath
        self.vaultedAt = vaultedAt
        self.expiresAt = expiresAt
        self.originalSize = originalSize
        self.sha256 = sha256
        self.parentSessionId = parentSessionId
        self.status = status
    }
}

/// One cleanup batch: the set of files moved to Trash + Vault together.
public struct CleanupSession: Sendable, Identifiable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let profileType: String
    public let totalReclaimable: Int64
    public let vaultItemIds: [UUID]

    public init(
        id: UUID,
        timestamp: Date,
        profileType: String,
        totalReclaimable: Int64,
        vaultItemIds: [UUID]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.profileType = profileType
        self.totalReclaimable = totalReclaimable
        self.vaultItemIds = vaultItemIds
    }
}

/// Per-file failure surfaced by a vault move.
public struct VaultMoveFailure: Sendable, Equatable {
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }
}

/// Outcome of `VaultManager.moveToTrash`: what was trashed, and what failed.
public struct VaultMoveResult: Sendable, Equatable {
    /// Nil when nothing was trashed.
    public let session: CleanupSession?
    public let items: [VaultItem]
    public let failures: [VaultMoveFailure]

    public init(session: CleanupSession?, items: [VaultItem], failures: [VaultMoveFailure]) {
        self.session = session
        self.items = items
        self.failures = failures
    }
}
