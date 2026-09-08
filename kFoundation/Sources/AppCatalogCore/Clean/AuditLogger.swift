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
        // opens always succeed, then append atomically.
        //
        // Concurrency notes:
        // - Within a single process, the actor serialises every `log` call so
        //   there is no race between the `fileExists` check and the
        //   `FileHandle(forWritingTo:)` open — both observe the file in the
        //   same serialised execution.
        // - Across processes (e.g. two kFresh instances writing to the same
        //   log) the `fileExists` → `FileHandle(forWritingTo:)` window can
        //   race; one process may create, the other may then clobber with a
        //   `createFile` (zero-length) and lose the first event. Multi-
        //   instance audit safety is a v1.1 follow-up — for v1 we accept that
        //   only one kFresh process at a time writes to any given log.
        if !fileManager.fileExists(atPath: logURL.path) {
            guard fileManager.createFile(atPath: logURL.path, contents: data) else {
                throw NSError(domain: "AuditLogger", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "createFile failed for \(logURL.path)"])
            }
            return
        }

        let handle = try FileHandle(forWritingTo: logURL)
        // best-effort: close failure in defer is non-fatal
        // swiftlint:disable:next no_silent_try_question_mark
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    /// Returns the most recent `limit` audit events, newest first. Decode errors
    /// on individual lines are silently skipped (best-effort read).
    public func recentEvents(limit: Int) -> [AuditEvent] {
        // best-effort: log file may not exist yet on first launch
        // swiftlint:disable:next no_silent_try_question_mark
        guard let data = try? Data(contentsOf: logURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = data.split(separator: 0x0A)
        // best-effort: malformed lines are silently skipped
        // swiftlint:disable:next no_silent_try_question_mark
        let events = lines.reversed().compactMap { try? decoder.decode(AuditEvent.self, from: Data($0)) }
        return Array(events.prefix(limit))
    }
}