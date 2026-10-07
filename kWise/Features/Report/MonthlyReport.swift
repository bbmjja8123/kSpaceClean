// kWise/Features/Report/MonthlyReport.swift
//
// 月报数据模型 (v2.0 Phase 7) — locally-generated report data from the
// cleanup history + disk samples: weekly freed bytes, top categories,
// streak, and the disk-full forecast. Zero network.
//
// P2 T7 — 独立月报页已退役：叙事头（NarrativeHeaderModel）+
// TimelineView 的「本月」可展开区直接消费这份模型。视图/VM 删除，
// `ReportGenerator.generate` 是唯一入口（Phase7CreativeTests 钉住）。
import Foundation

// MARK: - Generator

public struct MonthlyReport: Equatable {
    public struct WeekBucket: Equatable, Identifiable {
        public let id: Int
        public let label: String
        public let freedBytes: Int64
    }

    public struct TopCategory: Equatable, Identifiable {
        public let id: String
        public let title: String
        public let freedBytes: Int64
    }

    public let periodLabel: String
    public let totalFreedBytes: Int64
    public let totalCleanups: Int
    public let weekly: [WeekBucket]
    public let topCategories: [TopCategory]
    public let currentStreak: Int
    public let forecast: DiskForecastEngine.ForecastResult
    /// 本月最大 5 个已清理项 (v2.6 R2-5) — 每项可跳转大文件工具深挖。
    public let topCleanedFiles: [CleanedFile]
}

public struct CleanedFile: Equatable, Identifiable {
    public let name: String
    public let size: Int64
    public var id: String { name }
}

public enum ReportGenerator {

    /// Builds the report for the trailing 4 weeks (relative to `now`).
    public static func generate(history: [CleanupHistoryItem],
                                streak: StreakState,
                                samples: [DiskSample],
                                now: Date = Date(),
                                calendar: Calendar = .current) -> MonthlyReport {
        let monthAgo = calendar.date(byAdding: .day, value: -28, to: now) ?? now
        let recent = history.filter { ($0.cleanedAt ?? .distantPast) >= monthAgo }

        // Weekly buckets, oldest → newest.
        var buckets: [MonthlyReport.WeekBucket] = []
        for week in (0..<4).reversed() {
            let start = calendar.date(byAdding: .day, value: -7 * (week + 1), to: now)!
            let end = calendar.date(byAdding: .day, value: -7 * week, to: now)!
            let freed = recent
                .filter { ($0.cleanedAt ?? .distantPast) >= start && ($0.cleanedAt ?? .distantPast) < end }
                .reduce(Int64(0)) { $0 + $1.size }
            buckets.append(MonthlyReport.WeekBucket(
                id: week,
                label: week == 0 ? "本周" : "\(week) 周前",
                freedBytes: freed
            ))
        }

        // Top categories by freed size.
        let byCategory = Dictionary(grouping: recent) { $0.categoryID ?? "other" }
        let top = byCategory
            .map { key, rows in
                MonthlyReport.TopCategory(
                    id: key,
                    title: Self.friendlyCategory(key),
                    freedBytes: rows.reduce(Int64(0)) { $0 + $1.size }
                )
            }
            .sorted { $0.freedBytes > $1.freedBytes }
            .prefix(5)
            .map { $0 }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy 年 M 月"

        let topFiles: [CleanedFile] = recent
            .sorted { $0.size > $1.size }
            .prefix(5)
            .map { CleanedFile(name: URL(fileURLWithPath: $0.path ?? "").lastPathComponent, size: $0.size) }

        return MonthlyReport(
            periodLabel: formatter.string(from: now),
            totalFreedBytes: recent.reduce(Int64(0)) { $0 + $1.size },
            totalCleanups: recent.count,
            weekly: buckets,
            topCategories: top,
            currentStreak: streak.currentStreak,
            forecast: DiskForecastEngine.forecast(samples: samples, now: now, calendar: calendar),
            topCleanedFiles: topFiles
        )
    }

    private static func friendlyCategory(_ id: String) -> String {
        // Human-readable names; raw IDs only ever surface for unknown keys.
        switch id {
        case "system.cache": return "系统缓存"
        case "app.cache": return "应用缓存"
        case "web.junk": return "上网垃圾"
        case "mail.attachment": return "邮件附件"
        case "dev.junk": return "开发者垃圾"
        case "system.log": return "系统日志"
        default: return id
        }
    }
}
