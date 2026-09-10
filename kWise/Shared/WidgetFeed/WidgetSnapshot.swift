// kWise/Shared/WidgetFeed/WidgetSnapshot.swift
//
// Widget data feed (v2.0 Phase 6, design decision D5).
//
// One atomically-replaced JSON file in the App Group container replaces the
// scattered `UserDefaults` keys the Phase-0 widget read — the app wrote
// `snapshot.usedFraction` and nothing else ever consumed it, so the widget
// rendered its neutral state forever. This file is compiled into BOTH the
// app and the widget extension: one Codable contract, one storage location.
//
// Streak/forecast fields are populated from Phase 7 surfaces; they are
// optional so the schema ships stable today.
import Foundation

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var generatedAt: Date
    public var disk: DiskInfo?
    public var lastCleanup: LastCleanup?
    public var streak: StreakInfo?
    public var topCategory: TopCategory?
    public var forecast: ForecastInfo?

    public struct DiskInfo: Codable, Equatable, Sendable {
        public var usedBytes: Int64
        public var totalBytes: Int64

        public var usedFraction: Double {
            totalBytes > 0 ? min(max(Double(usedBytes) / Double(totalBytes), 0), 1) : 0
        }

        public init(usedBytes: Int64, totalBytes: Int64) {
            self.usedBytes = usedBytes
            self.totalBytes = totalBytes
        }
    }

    public struct LastCleanup: Codable, Equatable, Sendable {
        public var freedBytes: Int64
        public var date: Date

        public init(freedBytes: Int64, date: Date) {
            self.freedBytes = freedBytes
            self.date = date
        }
    }

    public struct StreakInfo: Codable, Equatable, Sendable {
        public var currentStreak: Int
        public var longestStreak: Int

        public init(currentStreak: Int, longestStreak: Int) {
            self.currentStreak = currentStreak
            self.longestStreak = longestStreak
        }
    }

    public struct TopCategory: Codable, Equatable, Sendable {
        public var title: String
        public var size: Int64

        public init(title: String, size: Int64) {
            self.title = title
            self.size = size
        }
    }

    public struct ForecastInfo: Codable, Equatable, Sendable {
        public var daysToFull: Int
        public var isReliable: Bool

        public init(daysToFull: Int, isReliable: Bool) {
            self.daysToFull = daysToFull
            self.isReliable = isReliable
        }
    }

    public init(schemaVersion: Int = WidgetSnapshot.currentSchemaVersion,
                generatedAt: Date = Date(),
                disk: DiskInfo? = nil,
                lastCleanup: LastCleanup? = nil,
                streak: StreakInfo? = nil,
                topCategory: TopCategory? = nil,
                forecast: ForecastInfo? = nil) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.disk = disk
        self.lastCleanup = lastCleanup
        self.streak = streak
        self.topCategory = topCategory
        self.forecast = forecast
    }
}

// MARK: - Store

/// Reads/writes the snapshot file in the App Group container.
public struct WidgetSnapshotStore: Sendable {
    public let fileURL: URL?

    /// - Parameter fileURL: injectable for tests; production resolves the
    ///   App Group container (`group.app.kraftly.sclean`).
    public init(fileURL: URL? = nil) {
        // Test host runs the real app binary — it must never touch the App
        // Group container. The unsigned test host wedges inside `open` on
        // that path on this machine (same root cause as the CoreDataStack
        // XCTest guard; see project memory). Degrade to "no feed".
        let runningTests = fileURL == nil
            && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if runningTests {
            self.fileURL = nil
        } else if let fileURL {
            self.fileURL = fileURL
        } else if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.app.kraftly.sclean"
        ) {
            self.fileURL = container.appendingPathComponent("widget-snapshot.json")
        } else {
            // No App Group (tests, pre-entitlement runs): degrade to "no feed"
            // rather than writing somewhere the widget can never read.
            self.fileURL = nil
        }
    }

    /// Atomic replace (tmp + rename semantics via `.atomic`).
    public func write(_ snapshot: WidgetSnapshot) {
        guard let fileURL else { return }
        guard snapshot.schemaVersion == WidgetSnapshot.currentSchemaVersion else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Unknown/absent schema versions read as "no data" — the widget shows
    /// its neutral state instead of crashing on a stale feed.
    public func read() -> WidgetSnapshot? {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.schemaVersion == WidgetSnapshot.currentSchemaVersion
        else { return nil }
        return snapshot
    }

    /// Merge helper: keeps fields this writer doesn't own.
    public func update(_ mutate: (inout WidgetSnapshot) -> Void) {
        var snapshot = read() ?? WidgetSnapshot()
        mutate(&snapshot)
        snapshot.generatedAt = Date()
        write(snapshot)
    }
}
