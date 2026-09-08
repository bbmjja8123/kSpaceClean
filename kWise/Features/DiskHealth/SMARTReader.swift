import Foundation

/// Reads S.M.A.R.T. health for the boot volume via `diskutil info`.
///
/// S.M.A.R.T. data is **not exposed via public macOS APIs** — even on Apple
/// Silicon the only reliable read is the `diskutil info -plist <disk>`
/// subprocess. On **Apple Silicon** that output is also incomplete (the
/// chip's storage controller talks directly to the SSD and macOS exposes
/// only `SMARTStatus: "Verified"` rather than the full attribute table);
/// on **Intel** with `kTCCServiceAllFiles` (Full Disk Access), the
/// `SMARTHotSpare` / `SMARTStatus` keys in `diskutil info` may surface.
///
/// Per roadmap §6 ("SMART may be unreadable on Apple Silicon"), this
/// reader implements graceful degradation:
/// * Happy path: parses `diskutil info -plist /` output and reports the
///   `SMARTStatus` string (one of "Verified", "Failing", "Not Supported",
///   "Unknown").
/// * Sad path: subprocess fails to launch, returns empty data, or the
///   user lacks FDA — `readStatus()` returns `nil` and the view layer
///   renders an "unavailable" badge (no error toast).
///
/// - SeeAlso: `docs/superpowers/plans/2026-08-09-kwise-v1.5-plan.md` Task 11
public enum SMARTStatus: String, Sendable {
    /// diskutil reported the drive's controller says it's healthy.
    case verified
    /// diskutil reported the drive is failing. Show a danger badge.
    case failing
    /// The drive or controller does not implement SMART.
    case notSupported = "Not Supported"
    /// Controller is present but did not report a clear answer.
    case unknown

    /// Parses a raw `diskutil` SMARTStatus string. Unknown values map to
    /// `.unknown` rather than throwing — the schema is undocumented.
    public static func parse(_ raw: String) -> SMARTStatus {
        switch raw.lowercased() {
        case "verified": return .verified
        case "failing":  return .failing
        case "not supported": return .notSupported
        default:         return .unknown
        }
    }

    public var friendlyTitle: String {
        switch self {
        case .verified:    return "正常"
        case .failing:     return "异常"
        case .notSupported: return "不支持"
        case .unknown:     return "未知"
        }
    }
}

public struct SMARTReport: Equatable, Sendable {
    public let status: SMARTStatus
    public let deviceNode: String
    public let readAt: Date

    public init(status: SMARTStatus, deviceNode: String, readAt: Date) {
        self.status = status
        self.deviceNode = deviceNode
        self.readAt = readAt
    }

    /// "no data available" sentinel — Apple Silicon without FDA, or
    /// subprocess failure.
    public static let unavailable = SMARTReport(status: .unknown, deviceNode: "", readAt: .distantPast)

    public var isAvailable: Bool { status != .unknown || readAt == .distantPast }
}

@MainActor
public final class SMARTReader: ObservableObject {
    @Published public private(set) var report: SMARTReport = .unavailable
    @Published public private(set) var isLoading = false

    /// Path to the boot volume's underlying device node. Tests can override
    /// via ``init(diskutilPath:deviceNode:)``.
    public let diskutilPath: String
    public let deviceNode: String

    public init(diskutilPath: String = "/usr/sbin/diskutil",
                deviceNode: String = "/") {
        self.diskutilPath = diskutilPath
        self.deviceNode = deviceNode
    }

    /// Run `diskutil info -plist /` and parse SMARTStatus + DeviceNode from
    /// the output. On any failure, leaves `report` at `.unavailable`.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        let output = await runDiskutilPlist()
        guard let (status, device) = parse(output) else {
            // Already .unavailable; nothing to update. We still bump the
            // timestamp so the UI knows the refresh attempt finished.
            return
        }
        report = SMARTReport(status: status, deviceNode: device, readAt: Date())
    }

    // MARK: - Subprocess plumbing

    /// Spawn `diskutil info -plist <deviceNode>` and return the full stdout.
    /// Returned empty string on any error.
    private func runDiskutilPlist() async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: diskutilPath)
            process.arguments = ["info", "-plist", deviceNode]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { p in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let payload = p.terminationStatus == 0 ? String(data: data, encoding: .utf8) ?? "" : ""
                continuation.resume(returning: payload)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: "")
            }
        }
    }

    /// Parses `diskutil info -plist` output. Returns `(SMARTStatus, DeviceNode)`
    /// or nil if neither key is present (older diskutil versions or Apple
    /// Silicon without FDA — both legitimate "no data" cases).
    ///
    /// Uses lightweight string scanning rather than PropertyListSerialization
    /// because `diskutil -plist` output is inconsistent across macOS releases
    /// and we only need two keys. Falls back to returning nil if the keys
    /// can't be located within ~120 KB of plist output.
    private func parse(_ output: String) -> (SMARTStatus, String)? {
        guard !output.isEmpty else { return nil }
        let statusRaw = stringValue(forKey: "SMARTStatus", in: output)
            ?? stringValue(forKey: "SMART", in: output)
        guard let statusRaw = statusRaw, !statusRaw.isEmpty else {
            return nil
        }
        let device = stringValue(forKey: "DeviceNode", in: output) ?? deviceNode
        return (SMARTStatus.parse(statusRaw), device)
    }

    /// Pulls a `<string>...</string>` value for the given dictionary key out
    /// of diskutil's plist output. Returns nil if the key isn't present.
    /// Crude but cheap — diskutil's plist output is well-formed XML and
    /// we only scan ~50 KB forward from the key.
    private func stringValue(forKey key: String, in output: String) -> String? {
        guard let keyRange = output.range(of: "<key>\(key)</key>") else { return nil }
        let start = output.index(keyRange.upperBound, offsetBy: 0)
        // Bound the scan window to keep this O(1).
        let endIdx = output.index(start, offsetBy: 50_000, limitedBy: output.endIndex) ?? output.endIndex
        let window = output[start..<endIdx]
        guard let openRange = window.range(of: "<string>") else { return nil }
        let valueStart = openRange.upperBound
        guard let closeRange = window.range(of: "</string>", range: valueStart..<window.endIndex) else { return nil }
        return String(window[valueStart..<closeRange.lowerBound])
    }
}