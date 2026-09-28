// kWise/Features/Attribution/VolumeLayerReader.swift
//
// 卷层通道（spec §4.2）：APFS 本地快照是文件扫描器看不见的黑盒大头。
// Process 范式照抄 SMARTReader.runDiskutilPlist —— 沙箱内合法（先例已在生产）。
// 红线：status != 0 或解析失败 = .unreadable，调用方必须明示，禁止 0 冒充。
import Foundation

public struct APFSSnapshot: Equatable, Sendable {
    public let name: String
    public let createdDate: Date?

    public init(name: String, createdDate: Date?) {
        self.name = name
        self.createdDate = createdDate
    }
}

public enum VolumeLayerError: Error, Equatable {
    case unreadable
}

public protocol VolumeCommandRunning: Sendable {
    func run(arguments: [String]) async -> (status: Int32, stdout: String)
}

/// 生产实现：spawn `/usr/sbin/diskutil <arguments>`。
public struct DiskutilRunner: VolumeCommandRunning {
    public let executablePath: String

    public init(executablePath: String = "/usr/sbin/diskutil") {
        self.executablePath = executablePath
    }

    public func run(arguments: [String]) async -> (status: Int32, stdout: String) {
        await withCheckedContinuation { (continuation: CheckedContinuation<(Int32, String), Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { terminated in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let payload = terminated.terminationStatus == 0
                    ? (String(data: data, encoding: .utf8) ?? "")
                    : ""
                continuation.resume(returning: (terminated.terminationStatus, payload))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (1, ""))
            }
        }
    }
}

public struct VolumeLayerReader: Sendable {
    public let runner: VolumeCommandRunning
    public let volumePath: String

    public init(runner: VolumeCommandRunning = DiskutilRunner(), volumePath: String = "/") {
        self.runner = runner
        self.volumePath = volumePath
    }

    public func listSnapshots() async throws -> [APFSSnapshot] {
        let (status, stdout) = await runner.run(
            arguments: ["apfs", "listSnapshots", "-plist", volumePath])
        guard status == 0, let data = stdout.data(using: .utf8), !stdout.isEmpty else {
            throw VolumeLayerError.unreadable
        }
        return try Self.parseSnapshotPlist(data)
    }

    /// 解析 `diskutil apfs listSnapshots -plist` 输出。
    /// 顶层必须是数组；条目缺日期 → createdDate = nil（诚实缺省）。
    public static func parseSnapshotPlist(_ data: Data) throws -> [APFSSnapshot] {
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let topLevel = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: &format),
            let entries = topLevel as? [[String: Any]]
        else { throw VolumeLayerError.unreadable }
        return entries.map { entry in
            let name = (entry["Name"] as? String)
                ?? (entry["name"] as? String)
                ?? ""
            return APFSSnapshot(name: name, createdDate: Self.date(in: entry))
        }
    }

    private static func date(in entry: [String: Any]) -> Date? {
        for key in ["CreationDate", "SnapshotCreationDate", "Snapshot Creation Date"] {
            if let date = entry[key] as? Date { return date }
            if let string = entry[key] as? String {
                if let parsed = Self.stringDateFormatter.date(from: string) { return parsed }
            }
        }
        return nil
    }

    private static let stringDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()
}
