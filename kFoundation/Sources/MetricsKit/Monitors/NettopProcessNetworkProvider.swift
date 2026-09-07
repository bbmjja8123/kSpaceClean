#if canImport(Darwin)
import Foundation
import Darwin

/// Adapter boundary for sampling per-process upload/download byte counts.
///
/// The implementation calls `nettop` (a built-in macOS diagnostic tool)
/// in JSON mode and parses the `bytes_in` / `bytes_out` counters per
/// process. `nettop` requires no special privileges and runs on every
/// supported Mac, so this is the lowest-friction way to get accurate
/// per-PID network attribution without writing custom kernel code.
public protocol ProcessNetworkSampling: Sendable {
    /// Returns a `[pid: (download, upload)]` map. `download` and
    /// `upload` are cumulative byte counts since process start, *not*
    /// per-second rates — callers must diff between two samples to get
    /// throughput (see `NettopProcessNetworkProvider.sampleThroughput`).
    func sampleCumulative() throws -> [Int32: ProcessNetworkBytes]

    /// Run two `nettop` samples one second apart and diff them. Returns
    /// nil if the underlying samples fail (e.g. `nettop` missing on the
    /// system, which only happens on stripped macOS installs).
    func sampleThroughput() throws -> [Int32: ProcessNetworkBytes]
}

/// Byte counters as reported by `nettop`. Both fields are cumulative
/// since the process started its network stack; diff two samples to
/// compute a rate.
public struct ProcessNetworkBytes: Sendable, Equatable {
    public let download: UInt64
    public let upload: UInt64

    public init(download: UInt64, upload: UInt64) {
        self.download = download
        self.upload = upload
    }
}

/// Live implementation backed by `/usr/bin/nettop -p <pid> -J bytes_in,bytes_out -l 1`.
public final class NettopProcessNetworkProvider: ProcessNetworkSampling, @unchecked Sendable {
    public init() {}

    public func sampleCumulative() throws -> [Int32: ProcessNetworkBytes] {
        let output = try runNettop()
        return try Self.parse(output)
    }

    public func sampleThroughput() throws -> [Int32: ProcessNetworkBytes] {
        let firstRaw = try runNettop()
        let first = try Self.parse(firstRaw)
        // Sleep 1.0s — long enough for non-zero diffs on active downloads,
        // short enough that the next UI refresh sees a fresh value.
        Thread.sleep(forTimeInterval: 1.0)
        let secondRaw = try runNettop()
        let second = try Self.parse(secondRaw)
        var rates: [Int32: ProcessNetworkBytes] = [:]
        for pid in second.keys {
            guard let now = second[pid], let before = first[pid] else { continue }
            let down = now.download >= before.download ? now.download - before.download : 0
            let up = now.upload >= before.upload ? now.upload - before.upload : 0
            rates[pid] = ProcessNetworkBytes(download: down, upload: up)
        }
        return rates
    }

    // MARK: - Private

    /// Runs `/usr/bin/nettop -J bytes_in,bytes_out -l 1` and returns the
    /// raw stdout. `nettop` accepts `-J <keys>` to limit JSON output
    /// fields; `bytes_in` / `bytes_out` are the cumulative counters.
    /// `-l 1` makes the command exit after one sample cycle instead of
    /// streaming forever.
    private func runNettop() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-J", "bytes_in,bytes_out", "-l", "1"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Parse `nettop`'s JSON output. The format is a heterogeneous array
    /// of dictionaries keyed by a process ID (`tcp4.tcp4.<pid>` etc.) —
    /// we extract the integer `<pid>` segment and the `bytes_in` /
    /// `bytes_out` integer fields. Returns `[pid: (download, upload)]`.
    static func parse(_ json: String) throws -> [Int32: ProcessNetworkBytes] {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data)
        else { return [:] }

        // nettop JSON is an array of [connection-key: metadata] dicts.
        // Each connection-key embeds the PID as the second `.`-separated
        // segment, e.g. `tcp4.tcp4.1234`. We accept any prefix.
        guard let entries = raw as? [Any] else { return [:] }

        var result: [Int32: ProcessNetworkBytes] = [:]
        for entry in entries {
            guard let dict = entry as? [String: Any] else { continue }
            for (key, value) in dict {
                guard let pid = pidFromKey(key), let meta = value as? [String: Any]
                else { continue }
                let down = (meta["bytes_in"] as? NSNumber)?.uint64Value ?? 0
                let up = (meta["bytes_out"] as? NSNumber)?.uint64Value ?? 0
                let existing = result[pid] ?? ProcessNetworkBytes(download: 0, upload: 0)
                result[pid] = ProcessNetworkBytes(
                    download: existing.download + down,
                    upload: existing.upload + up
                )
            }
        }
        return result
    }

    /// Extract the PID from a `nettop` connection-key such as
/// `tcp4.tcp4.1234`. Returns nil if the key has no trailing
/// integer segment.
private static func pidFromKey(_ key: String) -> Int32? {
    guard let lastSegment = key.split(separator: ".").last,
          let pid = Int32(lastSegment)
    else { return nil }
    return pid
}
}

/// Test double. Returns the canned throughput map verbatim.
public final class StubProcessNetworkProvider: ProcessNetworkSampling, @unchecked Sendable {
    private let throughput: [Int32: ProcessNetworkBytes]
    public init(throughput: [Int32: ProcessNetworkBytes] = [:]) {
        self.throughput = throughput
    }
    public func sampleCumulative() throws -> [Int32: ProcessNetworkBytes] { throughput }
    public func sampleThroughput() throws -> [Int32: ProcessNetworkBytes] { throughput }
}
#endif