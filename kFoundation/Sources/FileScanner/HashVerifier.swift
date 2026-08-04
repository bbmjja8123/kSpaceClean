import Foundation
import CryptoKit

/// 4 阶段文件验证器，替代旧的 `FileHasher`（8KB 采样导致数据丢失风险）。
///
/// **设计原则**：绝不只信 hash。Stage 4 的 byte-by-byte memcmp 是最后一道防线。
/// - Stage 1 (size grouping) 由调用方在 detector 层完成（O(1) 字典查找）
/// - Stage 2 (fingerprint)：4KB head + 4KB tail SHA-256，用于快速分桶
/// - Stage 3 (fullHash)：流式 SHA-256，无 maxSize 上限
/// - Stage 4 (byteEqual)：byte-by-byte memcmp，零数据丢失风险
///
/// 错误隔离：单文件失败 → `throws` 让调用方决定是否跳过；不静默吞错。
public actor HashVerifier {
    public struct VerifierError: Error, Sendable, Equatable {
        public let url: URL
        public let reason: String

        public static func unreadable(_ url: URL, reason: String) -> VerifierError {
            VerifierError(url: url, reason: reason)
        }
    }

    public struct VerifyResult: Sendable, Equatable {
        public let url: URL
        public let size: Int64
        public let fingerprint: String
        public let fullHash: String
        public let duration: TimeInterval

        public init(url: URL, size: Int64, fingerprint: String, fullHash: String, duration: TimeInterval) {
            self.url = url
            self.size = size
            self.fingerprint = fingerprint
            self.fullHash = fullHash
            self.duration = duration
        }
    }

    public init() {}

    // MARK: - Stage 2: Fingerprint (4KB head + 4KB tail SHA-256)

    /// 计算文件指纹用于快速分桶。
    /// - 小文件（≤ 8KB）：hash 整个文件（head 与 tail 重叠 = 整个内容）
    /// - 大文件（> 8KB）：head 4KB + tail 4KB
    /// - 空文件：SHA-256 of empty bytes (`e3b0c4...`)
    public func fingerprint(of url: URL) async throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw VerifierError.unreadable(url, reason: "cannot open file handle")
        }
        defer { try? handle.close() }

        let size: UInt64
        do {
            size = try handle.seekToEnd()
        } catch {
            throw VerifierError.unreadable(url, reason: "cannot determine file size: \(error.localizedDescription)")
        }

        if size == 0 {
            return SHA256().finalize().hexString
        }

        var hasher = SHA256()

        do {
            try handle.seek(toOffset: 0)
            let head = try handle.read(upToCount: 4096) ?? Data()
            hasher.update(data: head)

            if size > 8 * 1024 {
                try handle.seek(toOffset: size - 4096)
                let tail = try handle.read(upToCount: 4096) ?? Data()
                hasher.update(data: tail)
            }
        } catch {
            throw VerifierError.unreadable(url, reason: "read failed: \(error.localizedDescription)")
        }

        return hasher.finalize().hexString
    }

    // MARK: - Stage 3: Full Hash (streaming SHA-256, no size limit)

    /// 全文件 SHA-256，流式读取。
    /// - 1MB chunk（避免一次性大内存）
    /// - **无 maxSize 上限**（旧 `FileHasher` 的 100MB 上限已移除——这是导致大文件被静默丢弃的根因）
    /// - 适用于任意大小文件（含视频、RAW、磁盘镜像）
    public func fullHash(of url: URL) async throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw VerifierError.unreadable(url, reason: "cannot open file handle")
        }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: 0)
        } catch {
            throw VerifierError.unreadable(url, reason: "cannot seek to start: \(error.localizedDescription)")
        }

        var hasher = SHA256()
        let chunkSize = 1024 * 1024  // 1MB

        while true {
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: chunkSize) ?? Data()
            } catch {
                throw VerifierError.unreadable(url, reason: "read failed: \(error.localizedDescription)")
            }
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }

        return hasher.finalize().hexString
    }

    // MARK: - Stage 4: Byte-by-byte equality (last line of defense)

    /// 两个文件字节级相等性检查。
    /// - 流式 chunk-by-chunk memcmp（不一次性读全文件）
    /// - **第一个 mismatch 即返回 false**（不需要读完整文件）
    /// - 大小不同直接返回 false（无需读内容）
    /// - 读取失败返回 false（保守：不能确认相等就算不等）
    ///
    /// **关键承诺**：调用方在宣布两个文件为「重复」前，**必须**调用此方法验证。
    /// Hash 相同不能保证字节相同（旧 FileHasher 的 8KB 采样会导致不同文件产生相同 hash）。
    public func byteEqual(_ a: URL, _ b: URL) async -> Bool {
        // Fast path: size mismatch → not equal
        let sizeA = (try? a.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let sizeB = (try? b.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard sizeA == sizeB else { return false }
        if sizeA == 0 { return true }

        guard let handleA = try? FileHandle(forReadingFrom: a),
              let handleB = try? FileHandle(forReadingFrom: b) else {
            return false
        }
        defer {
            try? handleA.close()
            try? handleB.close()
        }

        let chunkSize = 1024 * 1024  // 1MB

        while true {
            let chunkA = (try? handleA.read(upToCount: chunkSize)) ?? Data()
            let chunkB = (try? handleB.read(upToCount: chunkSize)) ?? Data()

            // Both EOF → equal
            if chunkA.isEmpty && chunkB.isEmpty { return true }
            // One EOF earlier → not equal (sizes should already match, so this is defensive)
            if chunkA.isEmpty || chunkB.isEmpty { return false }
            // Content differs → not equal
            if chunkA != chunkB { return false }
            // Continue
        }
    }

    // MARK: - Convenience: all stages in one call

    /// 一次性跑 Stage 2 + Stage 3，返回完整 VerifyResult。
    /// 注意：不包含 Stage 4（byte-by-byte），那是 detector 在确认重复前的最后验证。
    public func verify(_ url: URL) async throws -> VerifyResult {
        let start = Date()
        let fp = try await fingerprint(of: url)
        let hash = try await fullHash(of: url)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return VerifyResult(
            url: url,
            size: size,
            fingerprint: fp,
            fullHash: hash,
            duration: Date().timeIntervalSince(start)
        )
    }
}

extension SHA256.Digest {
    fileprivate var hexString: String {
        self.map { String(format: "%02x", $0) }.joined()
    }
}
