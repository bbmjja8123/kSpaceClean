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

    public init(phase: ScanPhase, progress: Double, filesScanned: Int, duplicatesFound: Int) {
        self.phase = phase
        self.progress = progress
        self.filesScanned = filesScanned
        self.duplicatesFound = duplicatesFound
    }
}
