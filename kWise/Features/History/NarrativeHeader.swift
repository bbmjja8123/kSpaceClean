// kWise/Features/History/NarrativeHeader.swift
//
// 历史叙事头 (P2 T7) — the history page opens with a sentence, not a
// dashboard: 「这周你回收了 12.4 GB」+「磁盘比上周轻 6%」+「打卡 5 天 🔥」.
//
// Honesty rules (C-5): an empty week says so; a heavier disk is reported as
// heavier; missing disk samples are admitted instead of inventing a
// comparison. Zero network — inputs are the local cleanup history, the local
// disk-sample ring and the local streak ledger.
import Foundation

public enum NarrativeHeaderModel {

    /// One trailing-week sample spanning at least a week is the minimum for
    /// a week-over-week comparison; anything less is "采样不足".
    private static let minimumSamplesForComparison = 2

    /// Builds the narrative header lines from the local history + samples.
    ///
    /// - Parameters:
    ///   - records: cleanup history rows (all action kinds — shred and
    ///     startup-item removals recycle space just the same).
    ///   - samples: daily disk-usage samples (`DiskSampleStore`).
    ///   - streak: injected streak state; `nil` loads the App-Group ledger
    ///     (`StreakStore`) — the caller-facing default for production.
    ///   - now / calendar: injectable for tests.
    public static func build(records: [CleanupHistoryItem],
                             samples: [DiskSample],
                             streak: StreakState? = nil,
                             now: Date = Date(),
                             calendar: Calendar = .current)
    -> (headline: String, sub: String, streakLine: String?) {

        return (
            headline: weekHeadline(records: records, now: now, calendar: calendar),
            sub: diskSubline(samples: samples, now: now, calendar: calendar),
            streakLine: streakLine(streak: streak)
        )
    }

    // MARK: - Headline（这周你回收了 X）

    /// Trailing-7-days freed bytes — the same week window the report's
    /// 「本周」bucket uses, so the header and the 本月区 never disagree.
    static func weekHeadline(records: [CleanupHistoryItem],
                             now: Date,
                             calendar: Calendar) -> String {
        let weekStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let weekFreed = records
            .filter { ($0.cleanedAt ?? .distantPast) >= weekStart && ($0.cleanedAt ?? .distantPast) <= now }
            .reduce(Int64(0)) { $0 + $1.size }

        guard weekFreed > 0 else {
            // 空历史诚实零 — 不虚构回收量。
            return "这周还没有清理记录"
        }
        return "这周你回收了 \(SmartCareHeroView.formatBytes(weekFreed))"
    }

    // MARK: - Sub（磁盘比上周轻/重 X%）

    /// Week-over-week used-bytes comparison from the daily samples. The
    /// "now" reading is the newest sample; the "last week" reading is the
    /// newest sample at or before `now − 7d`.
    static func diskSubline(samples: [DiskSample],
                            now: Date,
                            calendar: Calendar) -> String {
        let sorted = samples.sorted { $0.day < $1.day }
        guard sorted.count >= minimumSamplesForComparison else {
            return "磁盘采样不足，暂无法与上周比较"
        }

        let weekAgoKey = DiskSampleStore.dayKey(
            for: calendar.date(byAdding: .day, value: -7, to: now) ?? now,
            calendar: calendar
        )
        guard let latest = sorted.last,
              let weekAgo = sorted.last(where: { $0.day <= weekAgoKey }),
              latest.day != weekAgo.day,
              weekAgo.usedBytes > 0
        else {
            return "磁盘采样不足，暂无法与上周比较"
        }

        // Round to a whole percent — sub-percent deltas read as noise.
        let deltaPercent = Int(((Double(latest.usedBytes - weekAgo.usedBytes)
                                 / Double(weekAgo.usedBytes)) * 100).rounded())

        if deltaPercent <= -1 {
            return "磁盘比上周轻 \(-deltaPercent)%"
        } else if deltaPercent >= 1 {
            // 变重也如实报告 — 粉饰等于撒谎（C-5）。
            return "磁盘比上周重 \(deltaPercent)%"
        }
        return "磁盘占用与上周基本持平"
    }

    // MARK: - Streak（打卡一行小字）

    /// One small line, no game panel. `nil` when the streak is zero —
    /// an empty ledger must not render a fabricated 打卡行.
    static func streakLine(streak: StreakState?) -> String? {
        let current = (streak ?? StreakStore().load()).currentStreak
        guard current >= 1 else { return nil }
        return "打卡 \(current) 天 🔥"
    }
}

// MARK: - Environment injection for the timeline view model

/// The local data the narrative header and the 本月区 read besides the
/// cleanup history. Injected per `refresh` so tests (and previews) never
/// touch the App-Group ledger or the sample ring file.
public struct NarrativeEnvironment: Sendable {
    public let samples: [DiskSample]
    public let streak: StreakState

    public init(samples: [DiskSample], streak: StreakState) {
        self.samples = samples
        self.streak = streak
    }

    /// Production default — local ring file + App-Group streak ledger.
    public static let live = NarrativeEnvironment(
        samples: DiskSampleStore().load(),
        streak: StreakStore().load()
    )
}
