//
//  SmokeUITests.swift
//  kWiseUITests
//
//  P3 Phase 5 UI 冒烟（plan §Phase5.4）。四个入口各一条用例，全部走
//  MAS scheme（kWise）真机容器：
//  1. Onboarding 3 页走通（授权页呈现 + 跳过语义，完成即落画布）；
//  2. 画布「+」菜单 → 应用卸载 sheet（M5 重接入口可达）；
//  3. 设置 → 启动项「管理」sheet（M2 重接入口可达）;
//  4. 未购买 → 维护「清理用户日志」→ 买断墙（R5 拒答路由，无静默执行）。
//
//  稳定性约定：
//  - 结构元素按 accessibilityIdentifier 查询（sheet/rail/菜单根），
//    文案元素按 zh-Hans 查询 —— 套件统一用 launch args 把 app 语言钉在
//    zh-Hans，不随测试机系统语言漂移；
//  - onboarding 由 `-onboarding.completed.v1` launch arg 覆盖
//    （@AppStorage 读 standard defaults，launch arg 天然覆盖），
//    自动首扫由 `-onboarding.autoScan.v1 YES` 压掉（FirstScanGate
//    读到已置位即不启动扫描）；
//  - 冒烟只断言「可达/呈现」，不执行任何真实清理 —— 唯一触发执行链的
//    买断墙用例在未购买态下走 R5 拒答（引擎全跳过，零删除），并在
//    已解锁（开发者模拟购买残留）时显式跳过。

import XCTest

final class SmokeUITests: XCTestCase {

    // MARK: - Fixtures

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // 把 app 语言钉在 zh-Hans：文案断言与系统语言解耦。
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// 跳过 onboarding 的启动（除 onboarding 用例外的三条都从这里进）。
    private func launchSkippingOnboarding() {
        app.launchArguments += ["-onboarding.completed.v1", "YES",
                                "-onboarding.autoScan.v1", "YES"]
        app.launch()
        // 画布就绪的标志：「+」菜单出现。
        XCTAssertTrue(waitForIdentifier("canvas.plusMenu"),
                      "跳过 onboarding 后画布「+」菜单应在 10s 内出现")
    }

    // MARK: - Helpers

    /// 按 identifier 等待任意元素类型出现（sheet 根 / 按钮 / 菜单在不同
    /// macOS 版本上落不同 element type，按类型查会碎）。
    @discardableResult
    private func waitForIdentifier(_ identifier: String,
                                   timeout: TimeInterval = 10) -> Bool {
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        return query.firstMatch.waitForExistence(timeout: timeout)
    }

    private func tapIdentifier(_ identifier: String, timeout: TimeInterval = 10) {
        let element = app.descendants(matching: .any)
            .matching(identifier: identifier).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "元素 \(identifier) 未在 \(timeout)s 内出现")
        // 分组表单里可能落在可视区外 —— 先尝试直接点，不行再滚到底。
        if element.isHittable {
            element.tap()
        } else {
            app.swipeUp()
            XCTAssertTrue(element.waitForExistence(timeout: 3), "滚动后仍未找到 \(identifier)")
            element.tap()
        }
    }

    /// SwiftUI Menu 在 macOS 上展开后，条目落在独立菜单窗口 —— XCUI 里
    /// 通常挂在 menuItems，个别版本挂在 buttons / any。按文案三路兜底。
    private func tapMenuItem(_ title: String) {
        let byMenu = app.menuItems[title]
        if byMenu.waitForExistence(timeout: 5) {
            byMenu.tap()
            return
        }
        let byButton = app.buttons[title]
        if byButton.waitForExistence(timeout: 2) {
            byButton.tap()
            return
        }
        let any = app.descendants(matching: .any).matching(
            NSPredicate(format: "title == %@", title)).firstMatch
        XCTAssertTrue(any.waitForExistence(timeout: 2), "菜单项「\(title)」未出现")
        any.tap()
    }

    // MARK: - 1. Onboarding（3 页走通）

    func testOnboardingWalkthroughLandsOnCanvas() throws {
        app.launchArguments += ["-onboarding.completed.v1", "NO",
                                "-onboarding.autoScan.v1", "YES"]
        app.launch()

        // 第 1 页：价值主张。
        XCTAssertTrue(waitForIdentifier("onboarding.container"),
                      "首启应弹出 onboarding sheet")
        XCTAssertTrue(app.staticTexts["更快,更干净"].waitForExistence(timeout: 5),
                      "第 1 页应呈现价值主张标题")

        // 第 2 页：扫描承诺 + 主目录授权合并页（MAS 沙盒授权块 + 跳过）。
        tapIdentifier("onboarding.nav.next")
        XCTAssertTrue(app.staticTexts["授权主目录访问"].waitForExistence(timeout: 5),
                      "第 2 页应呈现主目录授权块（MAS 渠道）")
        XCTAssertTrue(app.buttons["跳过此步骤"].exists,
                      "授权页必须提供跳过（诚实降级语义）")

        // 第 3 页：就绪页。
        tapIdentifier("onboarding.grant.skipButton")
        XCTAssertTrue(app.buttons["开始首次扫描"].waitForExistence(timeout: 5),
                      "第 3 页应呈现就绪态与首扫按钮")

        // 完成 → onboarding 关闭，落画布（自动首扫已被 launch arg 压掉）。
        tapIdentifier("onboarding.nav.done")
        // 先等画布就绪（「+」菜单出现），再确认 onboarding 已关闭 ——
        // sheet 消失有过渡动画，直接断言不存在会与动画竞态。
        XCTAssertTrue(waitForIdentifier("canvas.plusMenu", timeout: 10),
                      "完成 onboarding 后应落在主画布")
        XCTAssertFalse(waitForIdentifier("onboarding.container", timeout: 2),
                       "完成 onboarding 后 sheet 应关闭")
    }

    // MARK: - 2. 「+」菜单 → 应用卸载 sheet

    func testPlusMenuOpensUninstallSheet() throws {
        launchSkippingOnboarding()
        tapIdentifier("canvas.plusMenu")
        tapMenuItem("应用卸载…")
        XCTAssertTrue(waitForIdentifier("uninstall.sheet"),
                      "「+」菜单 → 应用卸载 应打开卸载 sheet")
    }

    // MARK: - 3. 设置 → 启动项「管理」sheet

    func testSettingsStartupItemsSheet() throws {
        launchSkippingOnboarding()
        tapIdentifier("rail.settings")
        XCTAssertTrue(app.staticTexts["启动项"].waitForExistence(timeout: 10),
                      "设置页应有「启动项」分区（P3 M2 重接入）")
        tapIdentifier("settings.startup.manage")
        XCTAssertTrue(waitForIdentifier("startup.sheet"),
                      "设置 → 启动项「管理」应打开启动项 sheet")
    }

    // MARK: - 4. 买断墙路由（R5 拒答，未购买态）

    func testPaywallRoutesWhenUnpurchased() throws {
        launchSkippingOnboarding()
        tapIdentifier("rail.settings")

        // 守卫：开发者本机若已解锁（模拟购买残留），跳过 —— 该用例只钉
        // 「未购买 → 拒答 → 买断墙」，不在已解锁态触发真实清理。
        let unlocked = app.staticTexts["已解锁"]
        if unlocked.waitForExistence(timeout: 3) {
            throw XCTSkip("开发机已拥有模拟买断 —— 跳过，避免触发真实清理链")
        }

        // 唯一 engine-backed 维护任务：清理用户日志。未购买 → 引擎 R5
        // 拒答（全跳过，零删除）→ quotaExhausted → 买断墙。
        tapIdentifier("settings.maintenance.clean.Clean user logs")
        XCTAssertTrue(waitForIdentifier("paywall.sheet", timeout: 15),
                      "未购买执行清理应路由买断墙（拒答，非静默跳过）")
    }
}
