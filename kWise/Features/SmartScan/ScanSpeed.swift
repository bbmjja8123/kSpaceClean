import Foundation
import FileScanner

/// 扫描速度档位，控制扫描过程中的 CPU 占用率
public enum ScanSpeed: String, Codable, CaseIterable, Sendable {
    /// 极速模式 — 不限制 CPU，扫描最快，可能影响 UI 响应
    case turbo = "turbo"
    /// 快速模式 — 较少让出 CPU，适合后台扫描
    case fast = "fast"
    /// 中等模式 — 平衡 CPU 占用与扫描速度（默认）
    case medium = "medium"
    /// 温和模式 — 最低 CPU 占用，适合前台工作时使用
    case gentle = "gentle"

    /// 每处理多少文件后让出 CPU
    public var batchSize: Int {
        switch self {
        case .turbo:  return 0      // 不让出
        case .fast:   return 500
        case .medium: return 100
        case .gentle: return 20
        }
    }

    /// 每次让出 CPU 时的休眠纳秒数（1ms = 1_000_000）
    public var sleepNanoseconds: UInt64 {
        switch self {
        case .turbo:  return 0
        case .fast:   return 0
        case .medium: return 1_000_000       // 1ms
        case .gentle: return 5_000_000       // 5ms
        }
    }

    public var displayName: String {
        switch self {
        case .turbo:  return "极速"
        case .fast:   return "快速"
        case .medium: return "中等"
        case .gentle: return "温和"
        }
    }

    public var description: String {
        switch self {
        case .turbo:  return "不限制 CPU，扫描最快，可能影响其他应用"
        case .fast:   return "较少占用 CPU，适合空闲时使用"
        case .medium: return "平衡 CPU 占用与扫描速度（推荐）"
        case .gentle: return "最低 CPU 占用，适合前台工作时使用"
        }
    }

    /// 文件枚举器的限流配置
    public var throttle: ThrottleConfig {
        ThrottleConfig(batchSize: batchSize, sleepNanoseconds: sleepNanoseconds)
    }
}
