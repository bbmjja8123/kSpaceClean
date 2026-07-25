import Foundation

public enum DuplicateCategory: String, Sendable, Codable, CaseIterable {
    case identical
    case directoryDedup
    case perceptual
    case largeFile
    case buildArtifact
    case rawJPEG
}

public struct DuplicateGroup: Sendable, Identifiable {
    public let id: UUID
    public let category: DuplicateCategory
    public let totalSize: Int64
    public let fileCount: Int
    public let files: [FileItem]

    public init(id: UUID, category: DuplicateCategory, totalSize: Int64, fileCount: Int, files: [FileItem]) {
        self.id = id
        self.category = category
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.files = files
    }
}

public struct FileItem: Sendable, Identifiable, Codable {
    public let id: UUID
    public let url: URL
    public let size: Int64
    public let modificationDate: Date
    public let hash: String?

    public init(id: UUID, url: URL, size: Int64, modificationDate: Date, hash: String?) {
        self.id = id
        self.url = url
        self.size = size
        self.modificationDate = modificationDate
        self.hash = hash
    }
}
