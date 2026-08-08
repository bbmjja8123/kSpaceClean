import Foundation

public struct ScanTarget: Sendable, Codable {
    public var directories: [String]
    public var exclusions: [String]
    public var minFileSize: Int64

    public init(directories: [String], exclusions: [String], minFileSize: Int64) {
        self.directories = directories
        self.exclusions = exclusions
        self.minFileSize = minFileSize
    }
}

public enum ScanPhase: String, Sendable {
    case enumerating
    case byteIdentical
    case directoryDedup
    case perceptual
    case largeFiles
    case buildArtifacts
    case rawJPEG
    case completed
}

public struct ScanProgress: Sendable {
    public let phase: ScanPhase
    public let progress: Double
    public let filesScanned: Int
    public let duplicatesFound: Int
    public let currentPath: String?

    public init(phase: ScanPhase, progress: Double, filesScanned: Int, duplicatesFound: Int, currentPath: String? = nil) {
        self.phase = phase
        self.progress = progress
        self.filesScanned = filesScanned
        self.duplicatesFound = duplicatesFound
        self.currentPath = currentPath
    }
}

/// A non-fatal issue encountered while scanning, surfaced to the UI without stopping the scan.
public struct ScanWarning: Sendable, Equatable {
    public let url: URL?
    public let message: String
    public let phase: ScanPhase

    public init(url: URL? = nil, message: String, phase: ScanPhase) {
        self.url = url
        self.message = message
        self.phase = phase
    }
}

/// Aggregated metrics emitted when a scan finishes.
public struct ScanSummary: Sendable, Codable {
    public let scanId: UUID
    public let timestamp: Date
    public let duration: TimeInterval
    public let filesScanned: Int
    public let bytesScanned: Int64
    public let groupsFound: Int
    public let totalReclaimable: Int64
    public let groupCounts: [DuplicateCategory: Int]

    public init(
        scanId: UUID,
        timestamp: Date,
        duration: TimeInterval,
        filesScanned: Int,
        bytesScanned: Int64,
        groupsFound: Int,
        totalReclaimable: Int64,
        groupCounts: [DuplicateCategory: Int]
    ) {
        self.scanId = scanId
        self.timestamp = timestamp
        self.duration = duration
        self.filesScanned = filesScanned
        self.bytesScanned = bytesScanned
        self.groupsFound = groupsFound
        self.totalReclaimable = totalReclaimable
        self.groupCounts = groupCounts
    }
}

/// A single event flowing out of a scan run. Results are carried as `.group` and
/// `.largeFiles` events so the UI can render them incrementally instead of waiting
/// for the whole scan to finish.
public enum ScanEvent: Sendable {
    case progress(ScanProgress)
    case group(duplicateGroup: DuplicateGroup)
    case largeFiles([FileItem])
    case warning(ScanWarning)
    case failed(String)
    case completed(ScanSummary)
}
