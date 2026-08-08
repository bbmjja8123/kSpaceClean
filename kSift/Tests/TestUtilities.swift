import Foundation
@testable import kSift

// MARK: - Temp File Helpers

/// Creates a unique temporary directory for use in a single test.
/// Caller is responsible for cleaning up with `FileManager.default.removeItem(at:)`.
func createTempDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ksift_test_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Creates a file at `directory` / `name` with exactly `size` bytes of zeroed content.
@discardableResult
func createTempFile(named name: String, in directory: URL, withSize size: Int64) throws -> URL {
    let url = directory.appendingPathComponent(name)
    let data = Data(count: Int(size))
    try data.write(to: url)
    return url
}

/// Creates a small text file at `directory` / `name` containing `content`.
@discardableResult
func createTextFile(named name: String, in directory: URL, content: String) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
}

/// Creates two files with identical textual content in the same directory.
/// - Returns: A tuple of the two file URLs.
@discardableResult
func createIdenticalFilePair(in directory: URL) throws -> (URL, URL) {
    let file1 = directory.appendingPathComponent("pair_a.txt")
    let file2 = directory.appendingPathComponent("pair_b.txt")
    let content = "identical content for testing kSift detectors"
    try content.write(to: file1, atomically: true, encoding: .utf8)
    try content.write(to: file2, atomically: true, encoding: .utf8)
    return (file1, file2)
}

// MARK: - Mock Factories

extension FileItem {
    /// Creates a `FileItem` with sensible defaults so tests can supply only the fields they care about.
    static func mock(
        id: UUID = UUID(),
        url: URL = URL(fileURLWithPath: "/tmp/default"),
        size: Int64 = 0,
        modificationDate: Date = Date(),
        creationDate: Date? = nil,
        hash: String? = nil,
        fingerprint: String? = nil,
        inode: UInt64? = nil,
        isAPFSClone: Bool = false,
        physicalSize: Int64? = nil
    ) -> FileItem {
        FileItem(
            id: id,
            url: url,
            size: size,
            modificationDate: modificationDate,
            creationDate: creationDate,
            hash: hash,
            fingerprint: fingerprint,
            inode: inode,
            isAPFSClone: isAPFSClone,
            physicalSize: physicalSize
        )
    }
}

extension DuplicateGroup {
    /// Creates a `DuplicateGroup` with sensible defaults so tests can supply only the fields they care about.
    static func mock(
        id: UUID = UUID(),
        category: DuplicateCategory = .identical,
        totalSize: Int64 = 0,
        fileCount: Int = 1,
        files: [FileItem] = [.mock()],
        categoryEvidence: CategoryEvidence? = nil,
        similarity: Double? = nil,
        scanTimestamp: Date = Date()
    ) -> DuplicateGroup {
        DuplicateGroup(
            id: id,
            category: category,
            totalSize: totalSize,
            fileCount: fileCount,
            files: files,
            categoryEvidence: categoryEvidence ?? mockEvidence(for: category, files: files),
            similarity: similarity,
            scanTimestamp: scanTimestamp
        )
    }

    private static func mockEvidence(
        for category: DuplicateCategory,
        files: [FileItem]
    ) -> CategoryEvidence {
        let first = files.first ?? .mock()
        switch category {
        case .identical:
            return .byteIdentical(sha256: first.hash ?? "mock-hash", byteVerified: true)
        case .directoryDedup:
            return .directoryDuplicate(contentHash: first.hash ?? "mock-hash", fileCount: files.count)
        case .perceptual:
            return .perceptualSimilarity(distance: 0, method: .visionFeaturePrint)
        case .largeFile:
            return .largeFile
        case .buildArtifact:
            return .buildArtifact(pattern: .genericBuild)
        case .rawJPEG:
            let second = files.dropFirst().first ?? first
            return .rawJPEGPair(rawFile: first, jpegFile: second, exifMatch: false)
        }
    }
}
