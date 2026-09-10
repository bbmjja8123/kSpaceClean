// kWise/Features/AppUninstall/HealthSummaryBuilder.swift
//
// AI 健康摘要卡 (v2.6)：可解释评级（无 AI 玄学）—— 残留/本体 比。
import Foundation
import AppCatalogCore
import CommonUtils

struct HealthSummary {
    enum Grade { case clean, normal, bloated }
    let daysInstalled: Int?
    let lastUsedText: String
    let totalSizeText: String
    let residueRatio: Double
    let grade: Grade
    let gradeText: String
}

enum HealthSummaryBuilder {

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
        if entry.isOrphan || entry.appSize == 0 || ratio > 0.5 {
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
