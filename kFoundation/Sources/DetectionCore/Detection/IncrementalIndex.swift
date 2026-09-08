import Darwin
import Foundation

/// The reusable proof that a file's content is unchanged since the last scan:
/// its fingerprint and full SHA-256, which the byte-identical detector can trust
/// without re-reading the file.
public struct CachedVerification: Sendable, Equatable {
    public let fingerprint: String
    public let hash: String

    public init(fingerprint: String, hash: String) {
        self.fingerprint = fingerprint
        self.hash = hash
    }
}

/// A single persisted entry in the incremental index.
public struct IncrementalIndexRecord: Sendable, Equatable {
    public let path: String
    public let size: Int64
    public let modificationDate: Date
    public let inode: UInt64?
    public let fingerprint: String
    public let hash: String

    public init(
        path: String,
        size: Int64,
        modificationDate: Date,
        inode: UInt64?,
        fingerprint: String,
        hash: String
    ) {
        self.path = path
        self.size = size
        self.modificationDate = modificationDate
        self.inode = inode
        self.fingerprint = fingerprint
        self.hash = hash
    }
}

public protocol IncrementalIndexRepositoryProtocol: Sendable {
    func loadRecords() async throws -> [IncrementalIndexRecord]
    func saveRecords(_ records: [IncrementalIndexRecord]) async throws
}

/// Persists and serves cached hashes so rescans only re-hash files that changed.
///
/// Trust model: a file whose (path, size, mtime, inode) all match the stored
/// record is assumed unchanged, so its stored fingerprint + SHA-256 are reused.
/// Only new or modified files are re-read from disk. The index is a paid feature
/// and is inert until the user unlocks it.
public protocol IncrementalIndexProtocol: Sendable {
    func prepare() async throws
    func cachedVerifications(for urls: [URL]) async -> [URL: CachedVerification]
    func update(files: [FileItem]) async
    func prune(keeping paths: Set<String>) async
    func persist() async throws
}

public actor IncrementalIndex: IncrementalIndexProtocol {
    /// A stat-derived signature compared against stored records.
    private struct FileSignature {
        let size: Int64
        let modificationDate: Date
        let inode: UInt64?
    }

    private let repository: any IncrementalIndexRepositoryProtocol
    private let isPaidUser: @Sendable () -> Bool

    /// Records keyed by absolute path.
    private var records: [String: IncrementalIndexRecord] = [:]
    private var loaded = false
    private var dirty = false

    public init(
        repository: any IncrementalIndexRepositoryProtocol,
        isPaidUser: @escaping @Sendable () -> Bool = { false }
    ) {
        self.repository = repository
        self.isPaidUser = isPaidUser
    }

    /// Loads the persisted index into memory. No-op until the user is paid, so
    /// free users never touch the repository.
    public func prepare() async throws {
        guard isPaidUser(), !loaded else { return }
        let stored = try await repository.loadRecords()
        var dict: [String: IncrementalIndexRecord] = [:]
        dict.reserveCapacity(stored.count)
        for record in stored {
            dict[record.path] = record
        }
        records = dict
        loaded = true
    }

    /// Returns a cached verification for every URL whose signature is unchanged.
    ///
    /// Uses a single `lstat` per URL (size + sub-second mtime + inode), which
    /// keeps matching fast even for very large trees.
    public func cachedVerifications(for urls: [URL]) async -> [URL: CachedVerification] {
        guard loaded, isPaidUser(), !records.isEmpty else { return [:] }
        var result: [URL: CachedVerification] = [:]
        result.reserveCapacity(urls.count)
        for url in urls {
            guard let record = records[url.path],
                  let signature = lstatSignature(of: url),
                  signature.size == record.size,
                  abs(signature.modificationDate.timeIntervalSince(record.modificationDate)) < 0.001,
                  record.inode == nil || signature.inode == record.inode
            else { continue }
            result[url] = CachedVerification(fingerprint: record.fingerprint, hash: record.hash)
        }
        return result
    }

    /// Upserts records for files that carry a hash + fingerprint. Files without
    /// either (e.g. large-file-only items) are skipped.
    public func update(files: [FileItem]) async {
        guard loaded, isPaidUser() else { return }
        for file in files {
            guard let hash = file.hash, let fingerprint = file.fingerprint else { continue }
            let record = IncrementalIndexRecord(
                path: file.url.path,
                size: file.size,
                modificationDate: file.modificationDate,
                inode: file.inode,
                fingerprint: fingerprint,
                hash: hash
            )
            if records[record.path] != record {
                records[record.path] = record
                dirty = true
            }
        }
    }

    /// Drops records whose paths no longer exist in the scan tree.
    public func prune(keeping paths: Set<String>) async {
        guard loaded, isPaidUser() else { return }
        let before = records.count
        records = records.filter { paths.contains($0.key) }
        if records.count != before {
            dirty = true
        }
    }

    /// Writes the in-memory index back to the repository, wholesale replacing
    /// the stored set. No-op unless something changed.
    public func persist() async throws {
        guard loaded, isPaidUser(), dirty else { return }
        try await repository.saveRecords(Array(records.values))
        dirty = false
    }

    // MARK: - Signature

    private func lstatSignature(of url: URL) -> FileSignature? {
        var info = stat()
        let status: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return Darwin.lstat(path, &info)
        }
        guard status == 0 else { return nil }
        return FileSignature(
            size: Int64(info.st_size),
            modificationDate: Date(
                timeIntervalSince1970: Double(info.st_mtimespec.tv_sec)
                    + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
            ),
            inode: UInt64(info.st_ino)
        )
    }
}
