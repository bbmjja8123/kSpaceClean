import Foundation
import SwiftUI

// MARK: - OnboardingCoordinator
//
// P2 T8 — 3 页收敛：欢迎（Page1）→ 扫描承诺 + 主目录授权合并页（Page2）→
// 完成即扫（Page3）。原 5 页中独立的隐私承诺页并入 Page2 的承诺区，独立
// 授权页并入 Page2 的授权区，独立就绪页保留为 Page3。

@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published var currentPage = 0

    let totalPages = 3
    var onComplete: (() -> Void)?

    // MARK: - Navigation

    /// Advance to the next page, or call onComplete on the last page.
    func next() {
        if currentPage < totalPages - 1 {
            currentPage += 1
        } else {
            onComplete?()
        }
    }

    /// Go back one page (UX 重构 Phase 1 — step indicator). No-op on page 0.
    func back() {
        guard currentPage > 0 else { return }
        currentPage -= 1
    }

    // MARK: - Grant Actions

    /// Skip the home-folder grant and jump directly to the ready-to-scan page.
    /// 扫描在 container-only 范围内仍可运行（诚实降级：可清理的组会变少）。
    func skipGrant() {
        currentPage = totalPages - 1
    }
}

// MARK: - FirstScanGate（P2 T8 — 首启自动扫描恰一次）

/// Onboarding 完成回调 → `anatomyViewModel.startScan()` 的门卫：
/// UserDefaults flag 保证「恰一次」。Onboarding 本就只出现一次，但幂等
/// 守卫仍要钉住（测试 / 预览 / 清除 onboarding.completed 标记的场景）。
enum FirstScanGate {
    static let flagKey = "onboarding.autoScan.v1"

    /// 未触发过 → 置位 flag 并返回 `true`（调用方应启动扫描）；
    /// 已触发过 → 返回 `false`（二次启动不再自动扫描）。
    @discardableResult
    static func shouldAutoScan(defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: flagKey) else { return false }
        defaults.set(true, forKey: flagKey)
        return true
    }
}
