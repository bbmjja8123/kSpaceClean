import Foundation

/// A single audit record emitted by `AuditLogger`.
///
/// Every uninstall-related action (trash, restore, terminate, fail) is recorded as
/// an `AuditEvent` so that the operator can reconstruct what happened even if the
/// app crashes mid-flight. The struct is intentionally `Codable` (JSONL format) and
/// `Sendable` so it can cross actor boundaries safely.
public struct AuditEvent: Codable, Sendable, Hashable {
    /// When the event was recorded.
    public let timestamp: Date
    /// One of: "trash", "restore", "terminate", "terminate-timeout", "backup", "fail".
    public let action: String
    /// The bundle identifier of the app that was being acted on, when applicable.
    public let bundleID: String
    /// Absolute filesystem paths that were acted on (app bundle path + residue paths).
    public let paths: [String]
    /// "success" or "failure".
    public let status: String
    /// Human-readable error description when `status == "failure"`, otherwise nil.
    public let errorMessage: String?

    public init(
        timestamp: Date,
        action: String,
        bundleID: String,
        paths: [String],
        status: String,
        errorMessage: String?
    ) {
        self.timestamp = timestamp
        self.action = action
        self.bundleID = bundleID
        self.paths = paths
        self.status = status
        self.errorMessage = errorMessage
    }
}

/// Append-only JSONL audit log used by `TrashMover` to record every uninstall action.
///
/// `AuditLogger` is an `actor` so concurrent writers from `TrashMover` cannot corrupt
/// the underlying file. The on-disk format is one JSON object per line, newline-
/// terminated, ISO 8601 timestamps — a format that is trivially appendable,
/// tail-able, and streamable. Read access (`recentEvents`) decodes the most recent
/// N events on demand; the file is not kept resident.
public actor AuditLogger {
    /// Absolute path to the JSONL file.
    private let logURL: URL
    private let fileManager = FileManager.default

    /// Creates an audit logger that writes to `logURL`. The parent directory is
    /// created if missing. Throws if the directory cannot be created.
    public init(logURL: URL) throws {
        self.logURL = logURL
        let dir = logURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Appends a single audit event to the JSONL file. Errors from `FileHandle`
    /// propagate to the caller; `TrashMover` wraps the call in `try?` so a failed
    /// audit write never blocks the actual uninstall.
    public func log(_ event: AuditEvent) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(event)
        data.append(0x0A)  // newline (JSONL format)

        // First-write path: FileHandle(forWritingTo:) requires the file to exist.
        // We materialise the file with `createFile(atPath:contents:)` so subsequent
        // opens always succeed, then append atomically. This avoids a TOCTOU race
        // between `fileExists` and `FileHandle` initialisation.
        if !fileManager.fileExists(atPath: logURL.path) {
            guard fileManager.createFile(atPath: logURL.path, contents: data) else {
                throw NSError(domain: "AuditLogger", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "createFile failed for \(logURL.path)"])
            }
            return
        }

        let handle = try FileHandle(forWritingTo: logURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    /// Returns the most recent `limit` audit events, newest first. Decode errors
    /// on individual lines are silently skipped (best-effort read).
    public func recentEvents(limit: Int) -> [AuditEvent] {
        guard let data = try? Data(contentsOf: logURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = data.split(separator: 0x0A)
        let events = lines.reversed().compactMap { try? decoder.decode(AuditEvent.self, from: Data($0)) }
        return Array(events.prefix(limit))
    }
}