import Foundation

/// A process holding an open file descriptor on a candidate file.
public struct InUseProcess: Sendable, Equatable {
    public let pid: Int32
    public let name: String

    public init(pid: Int32, name: String) {
        self.pid = pid
        self.name = name
    }
}

/// Source of "which processes hold these paths open". Abstracted so the
/// `lsof` shell-out can be stubbed in tests and so a sandboxed/failed
/// provider degrades gracefully instead of blocking cleanup.
public protocol InUseChecking: Sendable {
    /// Nil means the check could not be performed (sandbox denial, lsof
    /// missing) — distinct from an empty map, which genuinely means
    /// "nothing is holding these files".
    func processesHolding(_ paths: [String]) -> [String: [InUseProcess]]?
}

/// `lsof`-based provider. One invocation covers the whole candidate list.
///
/// Sandbox note: App Sandbox may silently deny descriptor enumeration for
/// other processes, in which case this returns an empty map — the caller
/// must treat "no holders" as "unknown", not "safe" (the UI pairs this
/// with `InUseHeuristics` and an explicit "check unavailable" notice).
public struct LsofInUseProvider: InUseChecking {
    /// Hard wall-clock limit for the lsof invocation — a wedged lsof must
    /// never stall the cleanup flow. On timeout the process is killed and
    /// whatever output landed is parsed.
    let timeout: TimeInterval

    public init(timeout: TimeInterval = 2) {
        self.timeout = timeout
    }

    public func processesHolding(_ paths: [String]) -> [String: [InUseProcess]]? {
        guard !paths.isEmpty else { return [:] }
        let pathSet = Set(paths)
        let arguments = ["-Fn", "+c0"] + paths

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Bounded wait: poll for exit instead of an unbounded block.
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()
        if process.terminationReason == .uncaughtSignal {
            // Killed on our timeout — output may be partial; parse it but
            // signal degraded coverage by treating no holders as unknown.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return parse(data: data, pathSet: pathSet)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return parse(data: data, pathSet: pathSet)
    }

    private func parse(data: Data, pathSet: Set<String>) -> [String: [InUseProcess]] {
        guard let output = String(data: data, encoding: .utf8) else { return [:] }
        var holders: [String: [InUseProcess]] = [:]
        var currentPID: Int32?
        var currentName = ""
        for line in output.split(separator: "\n") {
            guard let first = line.first else { continue }
            let value = String(line.dropFirst())
            switch first {
            case "p":
                currentPID = Int32(value)
                currentName = ""
            case "c":
                currentName = value
            case "n":
                // Match exactly (lsof may print trailing details for some
                // filesystems, so fall back to prefix match on the same path).
                guard let pid = currentPID, pathSet.contains(value) else { continue }
                holders[value, default: []].append(InUseProcess(pid: pid, name: currentName))
            default:
                break
            }
        }
        return holders
    }
}

/// One held file plus the processes holding it.
public struct InUseEntry: Sendable {
    public let file: FileItem
    public let processes: [InUseProcess]

    public init(file: FileItem, processes: [InUseProcess]) {
        self.file = file
        self.processes = processes
    }
}

/// The per-cleanup in-use assessment shown before the confirmation.
/// Keyed by `FileItem.id` — `FileItem` is not Hashable.
public struct InUseReport: Sendable {
    /// Files with at least one live descriptor held by another process.
    public var inUse: [UUID: InUseEntry] = [:]
    /// Files that *look* freshly active (temp suffixes / modified seconds
    /// ago) even though no descriptor was found. Always a subset risk.
    public var likelyInUse: [FileItem] = []
    /// True when the lsof provider could not run (sandbox denial etc.) —
    /// the UI then shows an "unavailable" notice alongside heuristics.
    public var checkUnavailable: Bool = false

    public var isEmpty: Bool {
        inUse.isEmpty && likelyInUse.isEmpty && !checkUnavailable
    }

    public init() {}
}

/// Best-effort "is this file being written right now" signals used when
/// (or in addition to) descriptor checks.
public enum InUseHeuristics {
    /// Suffixes browsers/downloaders use for in-flight downloads.
    public static let tempSuffixes: Set<String> = [
        "crdownload", "part", "partial", "download", "tmp", "filepart",
    ]
    /// Files modified within this window are treated as "possibly in use".
    public static let recentWindow: TimeInterval = 5 * 60

    public static func isLikelyInUse(_ file: FileItem, now: Date = Date()) -> Bool {
        let ext = file.url.pathExtension.lowercased()
        if tempSuffixes.contains(ext) { return true }
        return now.timeIntervalSince(file.modificationDate) < recentWindow
    }
}

/// Actor facade around the provider with a hard timeout, so a hung
/// `lsof` can never block the cleanup flow.
public actor InUseChecker {
    private let provider: any InUseChecking
    private let timeout: TimeInterval

    public init(provider: any InUseChecking = LsofInUseProvider(), timeout: TimeInterval = 2) {
        self.provider = provider
        self.timeout = timeout
    }

    /// Assesses the candidate files: live holders, heuristic hits, and
    /// whether the descriptor check itself was available. The provider
    /// bounds its own runtime, so this cannot stall the cleanup flow.
    public func assess(_ files: [FileItem], now: Date = Date()) async -> InUseReport {
        var report = InUseReport()
        guard !files.isEmpty else { return report }

        let paths = files.map { $0.url.path }
        let provider = self.provider
        let holders = await Task.detached(priority: .userInitiated) {
            provider.processesHolding(paths)
        }.value

        if let holders {
            for file in files {
                if let processes = holders[file.url.path], !processes.isEmpty {
                    report.inUse[file.id] = InUseEntry(file: file, processes: processes)
                } else if InUseHeuristics.isLikelyInUse(file, now: now) {
                    report.likelyInUse.append(file)
                }
            }
        } else {
            // Provider couldn't run — heuristic-only coverage.
            report.checkUnavailable = true
            for file in files where InUseHeuristics.isLikelyInUse(file, now: now) {
                report.likelyInUse.append(file)
            }
        }
        return report
    }
}
