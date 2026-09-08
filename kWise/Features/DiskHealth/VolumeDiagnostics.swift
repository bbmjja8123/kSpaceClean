import Foundation

/// Read-only volume diagnostics — file-system health signals for the boot
/// volume (read-only; no FDA required for `URLResourceValues` reads).
///
/// C-5 (精品 — 诚实 FDA 边界): every diagnostic carries a `requiresFDA`
/// flag so the view can render a single "已读 X GB / 需要 FDA Y GB" line
/// matching the pattern we in the top-cleaners gap analysis.
///
/// - SeeAlso: `docs/superpowers/plans/2026-08-09-kwise-v1.5-plan.md` Task 11
public struct VolumeDiagnostic: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case totalBytes
        case freeBytes
        case purgeableBytes  // Apple's "可清除" hint from volumeAvailableCapacityForImportantUsage
        case fileSystem
        case isInternal
        case isReadOnly
    }

    public let id: Kind
    public let title: String
    public let detail: String
    public let requiresFDA: Bool

    public init(kind: Kind, title: String, detail: String, requiresFDA: Bool = false) {
        self.id = kind
        self.title = title
        self.detail = detail
        self.requiresFDA = requiresFDA
    }
}

public struct VolumeSnapshot: Sendable {
    public let diagnostics: [VolumeDiagnostic]
    public let readAt: Date

    public init(diagnostics: [VolumeDiagnostic], readAt: Date) {
        self.diagnostics = diagnostics
        self.readAt = readAt
    }

    public var requiresFDACount: Int {
        diagnostics.filter(\.requiresFDA).count
    }

    public var totalBytes: Int64? {
        diagnostics.first(where: { $0.id == .totalBytes }).flatMap { Int64($0.detail) }
    }

    public var freeBytes: Int64? {
        diagnostics.first(where: { $0.id == .freeBytes }).flatMap { Int64($0.detail) }
    }

    public var purgeableBytes: Int64? {
        diagnostics.first(where: { $0.id == .purgeableBytes }).flatMap { Int64($0.detail) }
    }
}

@MainActor
public final class VolumeDiagnostics: ObservableObject {
    @Published public private(set) var snapshot: VolumeSnapshot
    @Published public private(set) var isLoading = false

    public init(snapshot: VolumeSnapshot = .empty) {
        self.snapshot = snapshot
    }

    /// Re-read the home volume's URLResourceValues. Doesn't need FDA; works
    /// in the sandbox and without sandbox alike.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let resourceValues = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeIsLocalKey,
            .volumeIsReadOnlyKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey
        ]) else {
            snapshot = .empty
            return
        }
        let total = Int64(resourceValues.volumeTotalCapacity ?? 0)
        let available = Int64(resourceValues.volumeAvailableCapacityForImportantUsage ?? 0)
        let used = max(0, total - available)
        var diagnostics: [VolumeDiagnostic] = []

        // Total bytes — does NOT need FDA; we always surface this.
        diagnostics.append(.init(
            kind: .totalBytes,
            title: "总容量",
            detail: String(total),
            requiresFDA: false
        ))
        // Used bytes — derived, no FDA.
        diagnostics.append(.init(
            kind: .freeBytes,
            title: "可用空间",
            detail: String(available),
            requiresFDA: false
        ))
        // Purgeable bytes hint — Apple's `volumeAvailableCapacityForImportantUsage`
        // is the most accurate "you can free this much" signal macOS exposes.
        diagnostics.append(.init(
            kind: .purgeableBytes,
            title: "可清理空间",
            detail: String(used),
            requiresFDA: false
        ))
        // File-system type — read via URLResourceValues doesn't surface it;
        // fall back to Process("diskutil info -plist") for the FilesystemName
        // key. Soft failure: missing detail just skips the row.
        if let fs = try? diskutilFilesystem() {
            diagnostics.append(.init(
                kind: .fileSystem,
                title: "文件系统",
                detail: fs,
                requiresFDA: false
            ))
        }
        diagnostics.append(.init(
            kind: .isInternal,
            title: "位置",
            detail: (resourceValues.volumeIsInternal ?? false) ? "内置" : "外接",
            requiresFDA: false
        ))
        diagnostics.append(.init(
            kind: .isReadOnly,
            title: "只读",
            detail: (resourceValues.volumeIsReadOnly ?? false) ? "是" : "否",
            requiresFDA: false
        ))

        snapshot = VolumeSnapshot(diagnostics: diagnostics, readAt: Date())
    }

    /// `diskutil info -plist /` parser for FilesystemName only. Returns nil
    /// on any failure — the view treats it as a cosmetic detail.
    private func diskutilFilesystem() throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", "/"]
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        guard let keyRange = output.range(of: "<key>FilesystemName</key>") else { return nil }
        let after = output[keyRange.upperBound...]
        guard let openRange = after.range(of: "<string>") else { return nil }
        let valueStart = openRange.upperBound
        guard let closeRange = after.range(of: "</string>", range: valueStart..<after.endIndex) else { return nil }
        return String(after[valueStart..<closeRange.lowerBound])
    }
}

extension VolumeSnapshot {
    /// Empty sentinel — used when `URLResourceValues` lookup fails or the
    /// reader hasn't run yet.
    public static let empty = VolumeSnapshot(
        diagnostics: [],
        readAt: .distantPast
    )
}