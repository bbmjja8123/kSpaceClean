import Foundation
import CryptoKit
import CommonUtils

public actor FileHasher {
    public enum HashError: Error {
        case fileTooLarge(Int64)
        case readFailed(URL)
    }

    public init() {}

    public func hash(file url: URL, maxSize: Int64 = 100 * 1024 * 1024) async throws -> String {
        let size = url.fileSize
        guard size <= maxSize else { throw HashError.fileTooLarge(size) }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        // SHA-256 of first 4KB + last 4KB (fast fingerprint for dedup)
        var hasher = SHA256()
        let frontData = try handle.read(upToCount: 4096) ?? Data()
        hasher.update(data: frontData)
        let endOffset = try handle.seekToEnd()
        // `offset` is UInt64 — clamp before subtracting so files smaller
        // than the 4KB window don't underflow (arithmetic-overflow trap).
        let tailOffset = endOffset > 4096 ? endOffset - 4096 : 0
        try handle.seek(toOffset: tailOffset)
        let tailData = try handle.read(upToCount: 4096) ?? Data()
        hasher.update(data: tailData)

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
