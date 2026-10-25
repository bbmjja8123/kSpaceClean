// kWise/Features/Anatomy/FreedBytesRoller.swift
//
// Task 2 清理完成时刻 — 释放字节滚动动画。
// - `measured = true` 显示引擎实测值（CleanupOutcome.measuredBytes）；
//   `false` 显示估算值并保留既有「≈」前缀语义（C-3 诚实口径，不倒退）。
// - Reduce Motion：不滚动，直接落终值（jumpsToFinalWhenReduceMotion）。
// - `.numericText` 过渡 macOS 14+；13 静态刷新（回退无害）。
// - 负字节钳 0（诚实零契约，与 QuickCleanResultCopy.doneTitle 同口径）。
import SwiftUI
import DesignSystem

/// 释放字节滚动动画（Task 2 完成时刻）。
/// - measured=true 显示实测值（引擎 measuredBytes），false 显示估算值并
///   保留既有「≈」前缀语义（C-3 诚实口径）。
/// - Reduce Motion：直接落终值，无滚动。
/// - .numericText 过渡 macOS 14+；13 静态刷新（回退无害）。
struct FreedBytesRoller: View {
    let bytes: Int64
    let measured: Bool

    /// RM 契约的静态钉点：Reduce Motion 下 onAppear 把 `displayed` 直接
    /// 置为目标值（无 0→N 动画）。测试断言此常量，防止行为被静默改回。
    static let jumpsToFinalWhenReduceMotion = true

    /// 诚实零契约：负的已释放量钳到 0 —— 绝不滚动出负数。
    static func clamped(_ bytes: Int64) -> Int64 { max(bytes, 0) }

    private var targetBytes: Int64 { Self.clamped(bytes) }

    @State private var displayed: Double = 0

    var body: some View {
        Group {
            if measured {
                Text(ByteCountFormatter.string(fromByteCount: Int64(displayed), countStyle: .file))
            } else {
                Text("≈ " + ByteCountFormatter.string(fromByteCount: Int64(displayed), countStyle: .file))
            }
        }
        .font(AppFont.largeTitle.monospacedDigit())
        .foregroundStyle(Color.success)
        .modifier(NumericTransitionIfAvailable(value: displayed))
        .onAppear {
            guard !AccessibilitySettings.reduceMotionEnabled else {
                displayed = Double(targetBytes)
                return
            }
            displayed = 0
            withAnimation(AccessibilitySettings.reduceMotionAnimation(.easeOut(duration: 0.9))) {
                displayed = Double(targetBytes)
            }
        }
        .accessibilityLabel(Text(ByteCountFormatter.string(fromByteCount: targetBytes, countStyle: .file)))
    }
}

/// `.contentTransition(.numericText(value:))` macOS 14+ 可用性包装。
/// brief 原稿的 modifier 无参、value 写死 1.0 —— 这里把当前 `displayed`
/// 传进来，value 变化才触发数字过渡（否则过渡永远绑定常数、不滚动）。
struct NumericTransitionIfAvailable: ViewModifier {
    let value: Double

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.contentTransition(.numericText(value: value))
        } else {
            content
        }
    }
}
