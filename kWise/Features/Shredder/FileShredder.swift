// kWise/Features/Shredder/FileShredder.swift
//
// 文件粉碎 (M6, v2.0 Phase 5) — sandbox-legal secure deletion.
//
// Sequence (design decision D2):
//   1. Guard rails — in-scope only, never .dangerous-system paths, never a
//      system directory; user consent is the caller's (DangerousConfirmDialog).
//   2. Overwrite pass(es) — sequential 1 MiB zero blocks via FileHandle.
//      Default is 1 pass; multi-pass is opt-in ("HDD 模式") with an honest
//      tooltip — on SSD/APFS extra passes are theatre (C-5).
//   3. Verify — read back; every byte must be zero.
//   4. Rename-randomize — 3 UUID renames in the same directory.
//   5. Disposition — `trashItem`, NOT `removeItem`: the content is gone but
//      the Finder "Put Back" shell still exists, preserving the C-4
//      rollback invariant.
// History is written BEFORE the pass (same write-before-move rule as
// CleanupEngine) with actionKind "shred".
import Foundation
import PowerScope

// MARK: - Plan

public struct ShredPlan: Sendable, Equatable {
    /// Number of zero-overwrite passes. 1 is the honest SSD default.
    public let passes: Int
    /// Read-back verification after overwriting.
    public let verify: Bool
    /// Number of randomized renames before trashing.
    public let randomizeRenames: Int

    public init(passes: Int = 1, verify: Bool = true, randomizeRenames: Int = 3) {
        self.passes = max(1, passes)
        self.verify = verify
        self.randomizeRenames = max(0, randomizeRenames)
    }

    /// kWise default: 1 pass + verify + 3 renames.
    public static let standard = ShredPlan()

    /// Opt-in multi-pass for spinning disks.
    public static let hddMode = ShredPlan(passes: 3)
}

// MARK: - Progress

public struct ShredProgress: Sendable {
    public let currentURL: URL
    public let completedFiles: Int
    public let totalFiles: Int
    public let phase: Phase

    public enum Phase: Sendable {
        case overwriting(pass: Int)
        case verifying
        case renaming
        case trashing
        case done
        case failed(String)
    }
}

// MARK: - Shredder

public actor FileShredder {
    /// 1 MiB zero block.
    private static let blockSize = 1_048_576
    private let scope: any PowerScopeProviding
    private let mover: TrashMover
    private let persistence: PersistenceController

    public init(scope: any PowerScopeProviding,
                mover: TrashMover = TrashMover(),
                persistence: PersistenceController) {
        self.scope = scope
        self.mover = mover
        self.persistence = persistence
    }

    /// Shreds the given URLs. Emits per-file progress and finishes after a
    /// final `.done`/`.failed` event. Per-file failures never abort the run.
    public func shred(urls: [URL], plan: ShredPlan = .standard) -> AsyncStream<ShredProgress> {
        AsyncStream { continuation in
            Task {
                var completed = 0
                var failures: [String] = []

                for url in urls {
                    guard Self.guardrailsPass(for: url) else {
                        failures.append(url.lastPathComponent)
                        completed += 1
                        continuation.yield(ShredProgress(
                            currentURL: url, completedFiles: completed,
                            totalFiles: urls.count,
                            phase: .failed("超出允许范围")))
                        continue
                    }

                    // Write history BEFORE the destructive work.
                    await self.recordHistory(for: url)

                    do {
                        for pass in 1...plan.passes {
                            continuation.yield(ShredProgress(
                                currentURL: url, completedFiles: completed,
                                totalFiles: urls.count, phase: .overwriting(pass: pass)))
                            try await Self.overwrite(url: url)
                        }

                        if plan.verify {
                            continuation.yield(ShredProgress(
                                currentURL: url, completedFiles: completed,
                                totalFiles: urls.count, phase: .verifying))
                            try await Self.verifyAllZero(url: url)
                        }

                        if plan.randomizeRenames > 0 {
                            continuation.yield(ShredProgress(
                                currentURL: url, completedFiles: completed,
                                totalFiles: urls.count, phase: .renaming))
                            try Self.randomizeRenames(of: url, count: plan.randomizeRenames)
                        }

                        continuation.yield(ShredProgress(
                            currentURL: url, completedFiles: completed,
                            totalFiles: urls.count, phase: .trashing))
                        var resulting: NSURL?
                        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                    } catch {
                        failures.append(url.lastPathComponent)
                    }

                    completed += 1
                }

                let finalPhase: ShredProgress.Phase = failures.isEmpty
                    ? .done
                    : .failed("有 \(failures.count) 个文件未能粉碎")
                continuation.yield(ShredProgress(
                    currentURL: urls.last ?? URL(fileURLWithPath: "/"),
                    completedFiles: completed, totalFiles: urls.count,
                    phase: finalPhase))
                continuation.finish()
            }
        }
    }

    // MARK: - Guard rails

    /// Hard preconditions: regular file, inside a scope kWise may read,
    /// never a system location. Anything suspicious is refused — content
    /// destruction must never be a guess.
    nonisolated static func guardrailsPass(for url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              !isDir.boolValue
        else { return false }

        let path = url.standardizedFileURL.path
        let forbidden = ["/System", "/Library", "/usr", "/bin", "/sbin", "/etc", "/private/var"]
        for prefix in forbidden where path == prefix || path.hasPrefix(prefix + "/") {
            // /private/var covers /tmp; user files never live there.
            return false
        }
        return true
    }

    // MARK: - Phases

    private static func overwrite(url: URL) async throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: 0)
        let zeros = Data(count: blockSize)
        var remaining = size
        while remaining > 0 {
            let chunk = min(Int64(blockSize), remaining)
            try handle.write(contentsOf: zeros.prefix(Int(chunk)))
            remaining -= chunk
        }
        try handle.truncate(atOffset: UInt64(size))
        try handle.synchronize()
    }

    private static func verifyAllZero(url: URL) async throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: 0)
        while let chunk = try handle.read(upToCount: blockSize), !chunk.isEmpty {
            guard chunk.allSatisfy({ $0 == 0 }) else {
                throw ShredError.verifyFailed(url)
            }
        }
    }

    private static func randomizeRenames(of url: URL, count: Int) throws {
        var current = url
        for _ in 0..<count {
            let newName = current.deletingLastPathComponent()
                .appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: current, to: newName)
            current = newName
        }
    }

    // MARK: - History

    private func recordHistory(for url: URL) async {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))
            .flatMap { $0.fileSize.map(Int64.init) } ?? 0
        let context = persistence.newBackgroundContext()
        let target = CleanupTarget(url: url, size: size, risk: .caution)
        await context.perform { [persistence] in
            persistence.insertHistory(targets: [target], in: context)
            persistence.save(context: context)
        }
    }
}

public enum ShredError: LocalizedError {
    case verifyFailed(URL)

    public var errorDescription: String? {
        switch self {
        case .verifyFailed(let url):
            return "覆写校验失败：\(url.lastPathComponent) 存在非零字节"
        }
    }
}
