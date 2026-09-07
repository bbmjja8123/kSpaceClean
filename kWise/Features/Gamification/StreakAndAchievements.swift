// kWise/Features/Gamification/StreakAndAchievements.swift
//
// Quick Clean 打卡 + 成就 (v2.0 Phase 7, design decision D4).
//
// `StreakStore` is a Codable struct persisted in the App Group so the
// widget can render the streak. Evaluation is a pure function
// (`AchievementEngine.evaluate`) so streak boundaries and unlock rules are
// unit-testable without touching storage. Fed by the same CleanupEventSink
// stream as the quota ledger — one metering point, no double counting.
import Foundation

// MARK: - Streak state

public struct StreakState: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    /// Last cleanup day, `yyyy-MM-dd`.
    public var lastCleanupDay: String?
    public var currentStreak: Int = 0
    public var longestStreak: Int = 0
    public var totalCleanups: Int = 0
    public var totalFreedBytes: Int64 = 0
    public var unlockedBadgeIDs: [String] = []

    public init() {}
}

/// App-Group-backed persistence for `StreakState`.
public struct StreakStore: Sendable {
    public let defaults: UserDefaults?

    public init(defaults: UserDefaults? = UserDefaults(suiteName: "group.app.kraftly.sclean")) {
        self.defaults = defaults
    }

    private static let key = "kwise.streak.v1"

    public func load() -> StreakState {
        guard let defaults, let data = defaults.data(forKey: Self.key),
              let state = try? JSONDecoder().decode(StreakState.self, from: data)
        else { return StreakState() }
        return state
    }

    public func save(_ state: StreakState) {
        guard let defaults, let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

// MARK: - Streak logic (pure)

public enum StreakLogic {
    /// Records one cleanup on `day`. Same-day cleanups don't inflate the
    /// streak; consecutive days extend it; a gap resets it to 1.
    public static func recordCleanup(_ state: inout StreakState,
                                     freedBytes: Int64,
                                     on day: String,
                                     calendar: Calendar = .current) {
        if state.lastCleanupDay == day {
            state.totalCleanups += 1
            state.totalFreedBytes += freedBytes
            return
        }
        let yesterday = Self.shift(state.lastCleanupDay, days: -1, calendar: calendar)
        if state.lastCleanupDay != nil, day == yesterday {
            state.currentStreak += 1
        } else {
            state.currentStreak = 1
        }
        state.longestStreak = max(state.longestStreak, state.currentStreak)
        state.lastCleanupDay = day
        state.totalCleanups += 1
        state.totalFreedBytes += freedBytes
    }

    static func shift(_ dayKey: String?, days: Int, calendar: Calendar) -> String? {
        guard let dayKey else { return nil }
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return nil }
        let shifted = calendar.date(byAdding: .day, value: days, to: date)!
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

// MARK: - Achievements (pure)

public struct Achievement: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let icon: String

    public init(id: String, title: String, detail: String, icon: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.icon = icon
    }

    /// The full catalogue.
    public static let catalogue: [Achievement] = [
        Achievement(id: "first.cleanup", title: "初次清理", detail: "完成第一次清理", icon: "sparkles"),
        Achievement(id: "cleanup.10", title: "小试牛刀", detail: "累计清理 10 次", icon: "sparkles.rectangle.stack"),
        Achievement(id: "cleanup.50", title: "清理达人", detail: "累计清理 50 次", icon: "star"),
        Achievement(id: "freed.1g", title: "1 GB 里程碑", detail: "累计释放 1 GB 空间", icon: "externaldrive.badge.checkmark"),
        Achievement(id: "freed.10g", title: "10 GB 里程碑", detail: "累计释放 10 GB 空间", icon: "externaldrive.badge.timemachine"),
        Achievement(id: "freed.100g", title: "百 G 战神", detail: "累计释放 100 GB 空间", icon: "externaldrive.fill.badge.checkmark"),
        Achievement(id: "streak.3", title: "三日坚持", detail: "连续 3 天清理", icon: "flame"),
        Achievement(id: "streak.7", title: "一周成瘾", detail: "连续 7 天清理", icon: "flame.fill"),
        Achievement(id: "streak.30", title: "月度仪式", detail: "连续 30 天清理", icon: "trophy"),
    ]
}

public enum AchievementEngine {
    /// Returns the achievements newly unlocked by this state — already-
    /// unlocked badges are never re-emitted (`unlockedBadgeIDs` is the
    /// single source of unlock truth).
    public static func evaluate(_ state: StreakState) -> [Achievement] {
        var unlocked = Set(state.unlockedBadgeIDs)
        var newlyUnlocked: [Achievement] = []

        func unlock(_ id: String, when condition: Bool) {
            guard condition, !unlocked.contains(id) else { return }
            unlocked.insert(id)
            if let badge = Achievement.catalogue.first(where: { $0.id == id }) {
                newlyUnlocked.append(badge)
            }
        }

        unlock("first.cleanup", when: state.totalCleanups >= 1)
        unlock("cleanup.10", when: state.totalCleanups >= 10)
        unlock("cleanup.50", when: state.totalCleanups >= 50)
        unlock("freed.1g", when: state.totalFreedBytes >= 1_073_741_824)
        unlock("freed.10g", when: state.totalFreedBytes >= 10_737_418_240)
        unlock("freed.100g", when: state.totalFreedBytes >= 107_374_182_400)
        unlock("streak.3", when: state.currentStreak >= 3)
        unlock("streak.7", when: state.currentStreak >= 7)
        unlock("streak.30", when: state.currentStreak >= 30)

        return newlyUnlocked
    }
}

// MARK: - Sink

/// CleanupEventSink that feeds the streak ledger and the widget snapshot.
public struct StreakSink: CleanupEventSink {
    public let store: StreakStore
    public let snapshotStore: WidgetSnapshotStore
    public var calendar: Calendar = .current

    public init(store: StreakStore = StreakStore(),
                snapshotStore: WidgetSnapshotStore = WidgetSnapshotStore()) {
        self.store = store
        self.snapshotStore = snapshotStore
    }

    public func cleanupDidFinish(_ event: CleanupEvent) async {
        guard event.freedBytes > 0 else { return }
        var state = store.load()
        StreakLogic.recordCleanup(
            &state,
            freedBytes: event.freedBytes,
            on: DiskSampleStore.dayKey(for: event.date, calendar: calendar),
            calendar: calendar
        )
        let unlocked = AchievementEngine.evaluate(state)
        state.unlockedBadgeIDs += unlocked.map(\.id)
        store.save(state)

        // Mirror the streak into the widget feed.
        snapshotStore.update { snapshot in
            snapshot.streak = WidgetSnapshot.StreakInfo(
                currentStreak: state.currentStreak,
                longestStreak: state.longestStreak
            )
        }
    }
}
