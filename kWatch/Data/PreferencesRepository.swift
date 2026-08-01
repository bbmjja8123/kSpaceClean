import Foundation
import MetricsKit

public enum AlertOperator: String, Codable, Sendable {
    case above
    case below
}

/// Preferences that may be read and updated by kWatch presentation layers.
public protocol PreferencesRepositoryProtocol: Sendable {
    var menuBarMode: MenuBarMode { get set }
    var enabledKinds: Set<MetricKind> { get set }
    var samplingIntervalSeconds: Double { get set }
    var onboardingCompleted: Bool { get set }
    var launchAtLogin: Bool { get set }
}

/// App Group-backed user preferences for the production application.
public final class PreferencesRepository: PreferencesRepositoryProtocol, @unchecked Sendable {
    private let defaults: UserDefaults

    private static let menuBarModeKey = "kWatch.menuBarMode"
    private static let enabledKindsKey = "kWatch.enabledKinds"
    private static let samplingIntervalKey = "kWatch.samplingIntervalSeconds"
    private static let onboardingCompletedKey = "kWatch.onboardingCompleted"
    private static let launchAtLoginKey = "kWatch.launchAtLogin"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        registerDefaults()
    }

    public var menuBarMode: MenuBarMode {
        get {
            let rawValue = defaults.string(forKey: Self.menuBarModeKey) ?? MenuBarMode.trend.rawValue
            return MenuBarMode(rawValue: rawValue) ?? .trend
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.menuBarModeKey)
        }
    }

    public var enabledKinds: Set<MetricKind> {
        get {
            let rawValues = defaults.stringArray(forKey: Self.enabledKindsKey) ?? []
            return Set(rawValues.compactMap(MetricKind.init(rawValue:)))
        }
        set {
            defaults.set(newValue.map(\.rawValue).sorted(), forKey: Self.enabledKindsKey)
        }
    }

    public var samplingIntervalSeconds: Double {
        get { defaults.double(forKey: Self.samplingIntervalKey) }
        set { defaults.set(newValue, forKey: Self.samplingIntervalKey) }
    }

    public var onboardingCompleted: Bool {
        get { defaults.bool(forKey: Self.onboardingCompletedKey) }
        set { defaults.set(newValue, forKey: Self.onboardingCompletedKey) }
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Self.launchAtLoginKey) }
        set { defaults.set(newValue, forKey: Self.launchAtLoginKey) }
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Self.menuBarModeKey: MenuBarMode.trend.rawValue,
            Self.enabledKindsKey: [
                MetricKind.cpu.rawValue,
                MetricKind.memory.rawValue,
                MetricKind.disk.rawValue,
                MetricKind.network.rawValue
            ],
            Self.samplingIntervalKey: 2.0,
            Self.onboardingCompletedKey: false,
            Self.launchAtLoginKey: false
        ])
    }
}

/// In-memory preferences for tests and `TestAppContainer`.
public final class InMemoryPreferences: PreferencesRepositoryProtocol, @unchecked Sendable {
    public var menuBarMode: MenuBarMode = .trend
    public var enabledKinds: Set<MetricKind> = [.cpu, .memory, .disk, .network]
    public var samplingIntervalSeconds: Double = 2.0
    public var onboardingCompleted = false
    public var launchAtLogin = false

    public init() {}
}
