import Foundation

public enum CleanupMethod: String, Sendable, Codable {
    case trash
    case delete
}

public struct CleanupAction: Sendable, Identifiable {
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

public struct CleanupRecord: Sendable, Identifiable {
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
