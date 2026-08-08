import Foundation
import UniformTypeIdentifiers

public enum DuplicateCategory: String, Sendable, Codable, CaseIterable {
    case identical
    case directoryDedup
    case perceptual
    case largeFile
    case buildArtifact
    case rawJPEG
}

#if canImport(AppIntents)
import AppIntents

@available(macOS 14, *)
extension DuplicateCategory: AppEnum {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Category"
    }

    public static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [
            .identical: "Identical",
            .directoryDedup: "Directory Dedup",
            .perceptual: "Perceptual",
            .largeFile: "Large File",
            .buildArtifact: "Build Artifact",
            .rawJPEG: "RAW/JPEG",
        ]
    }
}
#endif

/// The algorithm used to establish perceptual similarity.
public enum PerceptualMethod: String, Sendable, Codable {
    case dHash
    case visionFeaturePrint
}

/// A recognized developer build-artifact pattern.
public enum BuildPattern: String, Sendable, Codable {
    case objectFile
    case pythonBytecode
    case javaClass
    case staticLibrary
    case nodeModules
    case swiftBuild
    case swiftPM
    case xcodeDerivedData
    case xcodeUserData
    case cocoaPods
    case gradle
    case genericBuild
    case nextCache
    case rustTarget
    case goVendor
    case carthageBuild
    case cache
}

/// The evidence used to place files in a result group.
public enum CategoryEvidence: Sendable, Codable {
    case byteIdentical(sha256: String, byteVerified: Bool)
    case apfsClone(sha256: String)
    case directoryDuplicate(contentHash: String, fileCount: Int)
    case perceptualSimilarity(distance: Double, method: PerceptualMethod)
    case rawJPEGPair(rawFile: FileItem, jpegFile: FileItem, exifMatch: Bool)
    case buildArtifact(pattern: BuildPattern)
    case largeFile
}

public struct DuplicateGroup: Sendable, Identifiable, Codable {
    public let id: UUID
    public let category: DuplicateCategory
    public let totalSize: Int64
    public let fileCount: Int
    public let files: [FileItem]
    public let categoryEvidence: CategoryEvidence
    public let similarity: Double?
    public let scanTimestamp: Date

    public init(
        id: UUID,
        category: DuplicateCategory,
        totalSize: Int64,
        fileCount: Int,
        files: [FileItem],
        categoryEvidence: CategoryEvidence,
        similarity: Double? = nil,
        scanTimestamp: Date = Date()
    ) {
        self.id = id
        self.category = category
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.files = files
        self.categoryEvidence = categoryEvidence
        self.similarity = similarity
        self.scanTimestamp = scanTimestamp
    }
}

public struct FileItem: Sendable, Identifiable, Codable {
    public let id: UUID
    public let url: URL
    public let size: Int64
    public let modificationDate: Date
    public let creationDate: Date?
    public let hash: String?
    public let fingerprint: String?
    public let inode: UInt64?
    public let isAPFSClone: Bool
    public let physicalSize: Int64?
    public let fileType: UTType?

    public init(
        id: UUID,
        url: URL,
        size: Int64,
        modificationDate: Date,
        creationDate: Date? = nil,
        hash: String? = nil,
        fingerprint: String? = nil,
        inode: UInt64? = nil,
        isAPFSClone: Bool = false,
        physicalSize: Int64? = nil,
        fileType: UTType? = nil
    ) {
        self.id = id
        self.url = url
        self.size = size
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.hash = hash
        self.fingerprint = fingerprint
        self.inode = inode
        self.isAPFSClone = isAPFSClone
        self.physicalSize = physicalSize
        self.fileType = fileType
    }

    /// Loads light metadata (size, dates, physicalSize, fileType) for a URL
    /// via a single `URL.resourceValues` call and wraps it in a `FileItem`.
    /// Returns nil if the URL is not a regular file (directories, symlinks
    /// to nothing, broken aliases).
    ///
    /// Used by every metadata-only detector so they share one stat-style
    /// pass instead of each calling `resourceValues` independently.
    public static func fromMetadata(_ url: URL) -> FileItem? {
        guard let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .totalFileAllocatedSizeKey,
            .isRegularFileKey,
        ]), values.isRegularFile == true else {
            return nil
        }
        return FileItem(
            id: UUID(),
            url: url,
            size: Int64(values.fileSize ?? 0),
            modificationDate: values.contentModificationDate ?? .distantPast,
            creationDate: values.creationDate,
            physicalSize: values.totalFileAllocatedSize.map(Int64.init),
            fileType: UTType(filenameExtension: url.pathExtension)
        )
    }
}
