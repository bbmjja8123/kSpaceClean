import Foundation
import MetricsKit
import DesignSystem

public enum AlertOperator: String, Codable, Sendable {
    case above
    case below
}

/// User-selectable theme preference.
///
/// `.system` follows the system appearance, `.light` and `.dark` force the
/// respective mode regardless of OS setting.
public enum ThemeMode: String, Codable, Sendable, CaseIterable {
    case light
    case dark
    case system
}

/// Preferences that may be read and updated by kWatch presentation layers.
public protocol PreferencesRepositoryProtocol: Sendable {
    var menuBarMode: MenuBarMode { get set }
    var enabledKinds: Set<MetricKind> { get set }
    var samplingIntervalSeconds: Double { get set }
    var onboardingCompleted: Bool { get set }
    var launchAtLogin: Bool { get set }
    var menuBarIconTheme: MenuBarIconTheme { get set }
    var perMetricMenuBar: Bool { get set }
    var menuBarOrder: [MetricKind] { get set }
    var themeMode: ThemeMode { get set }
    var sparklineThemeID: String { get set }
}

/// App Group-backed user preferences for the production application.
public final class PreferencesRepository: PreferencesRepositoryProtocol, @unchecked Sendable {
    private let defaults: UserDefaults

    private static let menuBarModeKey = "kWatch.menuBarMode"
    private static let enabledKindsKey = "kWatch.enabledKinds"
    private static let samplingIntervalKey = "kWatch.samplingIntervalSeconds"
    private static let onboardingCompletedKey = "kWatch.onboardingCompleted"
    private static let launchAtLoginKey = "kWatch.launchAtLogin"
    private static let menuBarIconThemeKey = "kWatch.menuBarIconTheme"
    private static let perMetricMenuBarKey = "kWatch.perMetricMenuBar"
    private static let menuBarOrderKey = "kWatch.menuBarOrder"
    private static let themeModeKey = "kWatch.themeMode"
    private static let sparklineThemeIDKey = "kWatch.sparklineThemeID"

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

    public var menuBarIconTheme: MenuBarIconTheme {
        get {
            guard let data = defaults.data(forKey: Self.menuBarIconThemeKey),
                  let theme = try? JSONDecoder().decode(MenuBarIconTheme.self, from: data) else {
                return .default
            }
            return theme
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.menuBarIconThemeKey)
        }
    }

    public var perMetricMenuBar: Bool {
        get { defaults.bool(forKey: Self.perMetricMenuBarKey) }
        set { defaults.set(newValue, forKey: Self.perMetricMenuBarKey) }
    }

    public var menuBarOrder: [MetricKind] {
        get {
            guard let raw = defaults.array(forKey: Self.menuBarOrderKey) as? [String] else {
                return MetricKind.menuBarDisplayOrder
            }
            let parsed = raw.compactMap(MetricKind.init(rawValue:))
            return parsed.isEmpty ? MetricKind.menuBarDisplayOrder : parsed
        }
        set {
            defaults.set(newValue.map(\.rawValue), forKey: Self.menuBarOrderKey)
        }
    }

    public var themeMode: ThemeMode {
        get {
            let rawValue = defaults.string(forKey: Self.themeModeKey) ?? ThemeMode.dark.rawValue
            return ThemeMode(rawValue: rawValue) ?? .dark
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.themeModeKey)
        }
    }

    public var sparklineThemeID: String {
        get {
            defaults.string(forKey: Self.sparklineThemeIDKey) ?? SparklineTheme.default.id
        }
        set {
            defaults.set(newValue, forKey: Self.sparklineThemeIDKey)
        }
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Self.menuBarModeKey: MenuBarMode.trend.rawValue,
            Self.enabledKindsKey: [
                MetricKind.cpu.rawValue,
                MetricKind.memory.rawValue,
                MetricKind.disk.rawValue,
                MetricKind.network.rawValue,
                MetricKind.gpu.rawValue
            ],
            Self.samplingIntervalKey: 2.0,
            Self.onboardingCompletedKey: false,
            Self.launchAtLoginKey: false,
            Self.perMetricMenuBarKey: false,
            Self.menuBarOrderKey: MetricKind.menuBarDisplayOrder.map(\.rawValue),
            Self.themeModeKey: ThemeMode.dark.rawValue,
            Self.sparklineThemeIDKey: SparklineTheme.default.id
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
    public var menuBarIconTheme: MenuBarIconTheme = .default
    public var perMetricMenuBar: Bool = false
    public var menuBarOrder: [MetricKind] = MetricKind.menuBarDisplayOrder
    public var themeMode: ThemeMode = .dark
    public var sparklineThemeID: String = SparklineTheme.default.id

    public init() {}
}
