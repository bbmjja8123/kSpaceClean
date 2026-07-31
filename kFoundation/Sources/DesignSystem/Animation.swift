import SwiftUI

/// Kraftly 统一动效 tokens。
///
/// 4 款 App（kSpaceClean / kWatch / kDupe / kFresh）的所有 SwiftUI 动画
/// 必须从此处引用时长与缩放系数，禁止在各 App 内硬编码数值。
///
/// 数值定义见 `CLAUDE.md` §5.4「动效语言（强制）」。
public enum KFAnimation {
    // MARK: - Durations

    /// 短动效时长（秒）：状态切换、按钮反馈等轻量过渡。
    public static let durationFast: Double = 0.2

    /// 标准动效时长（秒）：默认过渡时长，`smooth` / `easeInOut` 均基于此值。
    public static let durationNormal: Double = 0.35

    /// 长动效时长（秒）：页面级转场、大范围布局变化。
    public static let durationSlow: Double = 0.5

    // MARK: - Scale factors

    /// 按钮按下时的缩放系数，配合 `.scaleEffect()` 使用。
    public static let scaleTap: Double = 0.97

    /// 卡片 hover 时的缩放系数，配合 `.scaleEffect()` 使用。
    public static let scaleHover: Double = 1.02

    /// 列表插入动画的起始缩放系数（0.95 → 1.0），配合 `.scaleEffect()` 使用。
    public static let scaleInsert: Double = 0.95

    // MARK: - Animations

    /// macOS 14+ 首选动画曲线，使用 ``durationNormal`` 时长。
    ///
    /// macOS 13 请降级使用 ``easeInOut``。
    @available(macOS 14.0, *)
    public static var smooth: Animation {
        #if compiler(>=5.9)
        // Xcode 15+（macOS 14 SDK）：使用原生 .smooth。
        return Animation.smooth(duration: durationNormal)
        #else
        // Xcode 14（macOS 13 SDK）中 Animation.smooth 尚未声明，
        // 用等价的「无回弹 spring」近似，保证接口在两种 SDK 下都可编译。
        return Animation.spring(response: durationNormal, dampingFraction: 1.0, blendDuration: 0)
        #endif
    }

    /// 全版本可用的降级动画曲线，使用 ``durationNormal`` 时长。
    public static var easeInOut: Animation {
        Animation.easeInOut(duration: durationNormal)
    }
}
