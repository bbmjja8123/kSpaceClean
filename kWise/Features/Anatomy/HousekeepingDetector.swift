// kWise/Features/Anatomy/HousekeepingDetector.swift
//
// 家务三组检测器（Task 8）：iOS 设备备份 / 下载分诊 / 废纸篓大项。
// 沙盒契约（MasScanScope.md 同源）：homeURL 为 nil（container-only）时
// 返回空 —— 调用方负责上画布诊断，禁止静默丢弃。iOS 备份是「数据·注意」
// 徽章（删了本机备份不影响 iCloud），垃圾桶大项走永久移除（isPermanent）。
//
// 只读探测：全程零写入；不可读路径 try? 吞掉并跳过（不出错误组）。
import Foundation

/// 家务三组（Task 8）：`GroupKind.housekeeping(_:)` 的载荷类型。
public enum HousekeepingKind: String, Sendable, CaseIterable {
    /// iOS 设备整目录备份（本机备份，删除后不可恢复；iCloud 云备份不受影响）。
    case iosBackup
    /// Downloads 里 14 天未再打开的大文件。
    case staleDownloads
    /// 仍在废纸篓里占用空间的大项（处置即永久移除）。
    case trashLargeItems
}

/// 检测器的一条发现：一个可解释、可预演的清理目标。
public struct HousekeepingFinding: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let kind: HousekeepingKind
    public let url: URL
    public let title: String
    public let bytes: Int64
    /// 距最近一次打开/修改的整天数（nil = 该组不承诺「闲置天数」语义）。
    public let daysIdle: Int?

    public init(id: UUID = UUID(),
                kind: HousekeepingKind,
                url: URL,
                title: String,
                bytes: Int64,
                daysIdle: Int?) {
        self.id = id
        self.kind = kind
        self.url = url
        self.title = title
        self.bytes = bytes
        self.daysIdle = daysIdle
    }
}

/// 家务检测 seam —— 生产实现 `HousekeepingDetector`，测试注入 mock。
public protocol HousekeepingScanning: Sendable {
    /// `homeURL` 为 nil（container-only）→ 返回空（调用方上画布诊断）。
    func scan(homeURL: URL?) async -> [HousekeepingFinding]
}

public struct HousekeepingDetector: HousekeepingScanning {

    public init() {}

    /// 下载分诊阈值：14 天未再打开。
    public static let staleDays = 14
    /// Downloads / .Trash 顶层项入组下限（10 MB）。
    public static let minBytes: Int64 = 10_000_000

    public func scan(homeURL: URL?) async -> [HousekeepingFinding] {
        guard let homeURL else { return [] }
        var findings: [HousekeepingFinding] = []
        findings += iosBackups(home: homeURL)
        findings += staleDownloads(home: homeURL)
        findings += trashLargeItems(home: homeURL)
        return findings
    }

    // MARK: - iOS 设备备份

    /// `Library/Application Support/MobileSync/Backup/*` —— 每台设备一个
    /// 子目录，**整目录为一个 finding**（部分删除会让备份损坏，要么全保
    /// 要么全删）。子目录不可读/为空 → 跳过（不出 0 字节组）。
    private func iosBackups(home: URL) -> [HousekeepingFinding] {
        let backupRoot = home.appendingPathComponent(
            "Library/Application Support/MobileSync/Backup", isDirectory: true)
        let devices = (try? FileManager.default.contentsOfDirectory(
            at: backupRoot, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        return devices
            .filter { $0.hasDirectoryPath }
            .compactMap { deviceURL -> HousekeepingFinding? in
                guard let bytes = directorySize(deviceURL), bytes > 0 else { return nil }
                return HousekeepingFinding(kind: .iosBackup,
                                           url: deviceURL,
                                           title: deviceURL.lastPathComponent,
                                           bytes: bytes,
                                           daysIdle: nil)
            }
    }

    // MARK: - 下载分诊

    /// Downloads 顶层 > 10MB 且 14 天未再打开的项（contentAccessDate 缺失
    /// 时回退 modificationDate —— 只读探测，绝不 stat 风暴之外的写入）。
    private func staleDownloads(home: URL) -> [HousekeepingFinding] {
        largeTopLevelItems(in: home.appendingPathComponent("Downloads", isDirectory: true))
            .compactMap { url, bytes -> HousekeepingFinding? in
                guard let idleDate = lastAccessDate(of: url) else { return nil }
                let idle = Date().timeIntervalSince(idleDate)
                guard idle >= Double(Self.staleDays * 86_400) else { return nil }
                return HousekeepingFinding(kind: .staleDownloads,
                                           url: url,
                                           title: url.lastPathComponent,
                                           bytes: bytes,
                                           daysIdle: Int(idle) / 86_400)
            }
    }

    // MARK: - 废纸篓大项

    /// `~/.Trash` 顶层 > 10MB 的项 —— 这些空间只有「清倒」才真正释放；
    /// 处置走永久移除（isPermanent，RootView 垃圾桶组置 true）。
    private func trashLargeItems(home: URL) -> [HousekeepingFinding] {
        largeTopLevelItems(in: home.appendingPathComponent(".Trash", isDirectory: true))
            .map { url, bytes in
                HousekeepingFinding(kind: .trashLargeItems,
                                    url: url,
                                    title: url.lastPathComponent,
                                    bytes: bytes,
                                    daysIdle: nil)
            }
    }

    // MARK: - 共享探测原语

    /// 目录顶层 > `minBytes` 的项（文件或目录都算；目录按递归合计）。
    /// 不可读的项静默跳过 —— 只读探测，降级不报错。
    private func largeTopLevelItems(in directory: URL) -> [(URL, Int64)] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        return entries.compactMap { url -> (URL, Int64)? in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            let bytes: Int64
            if values?.isDirectory == true {
                bytes = directorySize(url) ?? 0
            } else {
                bytes = Int64(values?.fileSize ?? 0)
            }
            guard bytes > Self.minBytes else { return nil }
            return (url, bytes)
        }
    }

    /// 递归求和的字节数（不跟随符号链接；目录自身不计）。不可读 → nil。
    private func directorySize(_ url: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [], errorHandler: { _, _ in true }) else { return nil }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
                  values.isDirectory != true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    /// 「最后一次打开」时间：contentAccessDate 优先，缺失回退 modificationDate；
    /// 两者都拿不到 → nil（该项不入组 —— 不伪造闲置天数）。
    private func lastAccessDate(of url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentAccessDateKey, .contentModificationDateKey])
        return values?.contentAccessDate ?? values?.contentModificationDate
    }
}
