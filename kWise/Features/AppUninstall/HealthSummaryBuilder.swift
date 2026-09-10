// kWise/Features/AppUninstall/HealthSummaryBuilder.swift
//
// AI 健康摘要卡 (v2.6)：可解释评级（无 AI 玄学）—— 50MB 绝对阈值 + 残留/本体 比。
import Foundation
import CommonUtils

/// 单个 App 的健康摘要卡数据（卸载确认页 / 明细面板共用）。
struct HealthSummary {
    /// 可解释评级：`clean`（干净）/ `normal`（正常）/ `bloated`（臃肿）。
    enum Grade { case clean, normal, bloated }
    /// 安装至今天数（`installDate` 未知时为 `nil`）。
    let daysInstalled: Int?
    /// 最近使用的人话描述（未知时为 "未知"）。
    let lastUsedText: String
    /// 本体 + 残留 的总量文案（`FileSizeFormatter.abbreviated`）。
    let totalSizeText: String
    /// 残留 / 本体 体积比（本体为 0 时记 1.0）。
    let residueRatio: Double
    /// 评级（判定规则见 `HealthSummaryBuilder.build`）。
    let grade: Grade
    /// 评级的中文短文案：干净 / 正常 / 臃肿。
    let gradeText: String
}

enum HealthSummaryBuilder {

    /// 按固定优先级产出可解释评级（阈值即"可解释"的实现源头，逐条对用户展示）：
    /// 1. 孤儿（`isOrphan`）或本体大小为 0 → `.bloated`（残留即全部）
    /// 2. `leftoverSize < 50 MB` → `.clean`（绝对阈值优先于比率，小 App 不因高比率被误判）
    /// 3. `residueRatio > 0.5` → `.bloated`
    /// 4. `residueRatio >= 0.1` → `.normal`
    /// 5. 其余 → `.clean`
    ///
    /// - Parameters:
    ///   - entry: 扫描产出的待卸载应用条目
    ///   - now: 计算安装天数 / 相对时间 的基准时间（测试注入固定值防跨日界 flake）
    /// - Returns: 填充完毕的健康摘要
    static func build(for entry: UninstallAppEntry, now: Date = Date()) -> HealthSummary {
        let daysInstalled = entry.installDate.map {
            max(0, Calendar.current.dateComponents([.day], from: $0, to: now).day ?? 0)
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        let lastUsedText = entry.lastUsedDate.map {
            "最近使用是 " + formatter.localizedString(for: $0, relativeTo: now)
        } ?? "未知"

        let ratio = entry.appSize > 0
            ? Double(entry.leftoverSize) / Double(entry.appSize)
            : 1.0
        let grade: HealthSummary.Grade
        if entry.isOrphan || entry.appSize == 0 {
            grade = .bloated
        } else if entry.leftoverSize < 50 * 1_048_576 {
            grade = .clean
        } else if ratio > 0.5 {
            grade = .bloated
        } else if ratio >= 0.1 {
            grade = .normal
        } else {
            grade = .clean
        }
        let gradeText = switch grade {
        case .clean: "干净"
        case .normal: "正常"
        case .bloated: "臃肿"
        }
        let total = FileSizeFormatter.abbreviated(from: entry.appSize + entry.leftoverSize)

        return HealthSummary(
            daysInstalled: daysInstalled,
            lastUsedText: lastUsedText,
            totalSizeText: total,
            residueRatio: ratio,
            grade: grade, gradeText: gradeText
        )
    }
}
