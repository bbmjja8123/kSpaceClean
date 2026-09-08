// kWise/Features/DiskHealth/DiskForecast.swift
//
// Disk-usage sampling + "when will my disk be full" forecast
// (v2.0 Phase 7, design decision D3).
//
// Sampling is *opportunistic* — one sample per day, upserted on app launch
// and after cleanups. MAS policy forbids background agents, and the UI says
// so honestly ("按使用 kWise 时的采样"). Storage is a JSON ring file in the
// app container (400-day cap, ~2 KB) — not Core Data, not UserDefaults.
import Foundation

// MARK: - Samples

public struct DiskSample: Codable, Equatable, Sendable {
    /// Day key `yyyy-MM-dd` — one sample per day (last write wins).
    public let day: String
    public let usedBytes: Int64
    public let totalBytes: Int64

    public init(day: String, usedBytes: Int64, totalBytes: Int64) {
        self.day = day
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
    }
}

/// JSON ring store for daily disk samples.
public struct DiskSampleStore: Sendable {
    public static let maxSamples = 400
    public let fileURL: URL?

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first?.appendingPathComponent("app.kraftly.sclean", isDirectory: true)
            self.fileURL = dir?.appendingPathComponent("usage-samples.json")
        }
    }

    public static func dayKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func load() -> [DiskSample] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let samples = try? JSONDecoder().decode([DiskSample].self, from: data)
        else { return [] }
        return samples
    }

    /// Upsert today's sample and cap the ring.
    public func upsert(usedBytes: Int64, totalBytes: Int64, now: Date = Date()) {
        guard let fileURL else { return }
        var samples = load()
        let key = Self.dayKey(for: now)
        samples.removeAll { $0.day == key }
        samples.append(DiskSample(day: key, usedBytes: usedBytes, totalBytes: totalBytes))
        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }
        if let data = try? JSONEncoder().encode(samples) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Sampler

/// Records today's usage. Fired from app launch and the cleanup sink —
/// the engine already measures volume deltas, so this piggybacks for free.
public struct DiskUsageSampler: Sendable {
    public let store: DiskSampleStore

    public init(store: DiskSampleStore = DiskSampleStore()) {
        self.store = store
    }

    public func sample(now: Date = Date()) {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? homeURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        ) else { return }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        store.upsert(usedBytes: max(0, total - available), totalBytes: total, now: now)
    }
}

// MARK: - Forecast

public enum DiskForecastEngine {

    public enum ForecastResult: Equatable {
        /// Fewer than 2 samples — no prediction (never fabricate, C-5).
        case insufficientData
        /// Usage isn't trending up meaningfully.
        case stable
        /// Reliable upward trend — predicted days until the volume is full.
        case filling(daysToFull: Int, r2: Double)
    }

    /// Ordinary-least-squares trend over the most recent `window` samples.
    ///
    /// r² < 0.5 reads as noise → `.stable` with a "波动较大" footnote in the
    /// UI. Predictions past 365 days read as `.stable` too — "你的磁盘还能
    /// 用很久" is the honest version of a 4-digit day count.
    public static func forecast(samples: [DiskSample],
                                window: Int = 30,
                                now: Date = Date(),
                                calendar: Calendar = .current) -> ForecastResult {
        let recent = samples.sorted { $0.day < $1.day }.suffix(window)
        guard recent.count >= 2 else { return .insufficientData }

        // x = days since the first sample in the window, y = used bytes.
        let base = recent.first!.day
        let points: [(x: Double, y: Double)] = recent.map { sample in
            let dayStart = calendar.startOfDay(for: Self.parse(sample.day, calendar: calendar) ?? now)
            let origin = calendar.startOfDay(for: Self.parse(base, calendar: calendar) ?? now)
            let x = Double(calendar.dateComponents([.day], from: origin, to: dayStart).day ?? 0)
            return (x, Double(sample.usedBytes))
        }

        let n = Double(points.count)
        let sumX = points.reduce(0) { $0 + $1.x }
        let sumY = points.reduce(0) { $0 + $1.y }
        let meanX = sumX / n
        let meanY = sumY / n
        let covariance = points.reduce(0.0) { $0 + ($1.x - meanX) * ($1.y - meanY) }
        let varianceX = points.reduce(0.0) { $0 + pow($1.x - meanX, 2) }
        let varianceY = points.reduce(0.0) { $0 + pow($1.y - meanY, 2) }

        guard varianceX > 0, varianceY > 0 else { return .stable }
        let slope = covariance / varianceX
        let intercept = meanY - slope * meanX
        let r = covariance / (varianceX.squareRoot() * varianceY.squareRoot())
        let r2 = r * r

        // Not rising meaningfully, or the fit is noise.
        guard slope > 0, r2 >= 0.5 else { return .stable }

        guard let capacity = recent.last?.totalBytes, capacity > 0 else { return .stable }
        let usedNow = intercept + slope * meanX
        let remaining = Double(capacity) - usedNow
        guard remaining > 0 else { return .filling(daysToFull: 0, r2: r2) }

        let days = remaining / slope
        guard days < 365 else { return .stable }
        return .filling(daysToFull: Int(days.rounded()), r2: r2)
    }

    private static func parse(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
