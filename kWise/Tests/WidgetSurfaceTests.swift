// WidgetSurfaceTests.swift
//
// Task 11 — Control Center quick-clean control widget (macOS 15+ gated).
// Source-level audit: the widget extension target has no test host that can
// render a ControlWidget, so the contract is pinned at the declaration level.
import XCTest

final class WidgetSurfaceTests: XCTestCase {
    func testControlWidgetDeclaredWithAvailabilityGate() {
        let src = (try? String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../Widgets/kWiseWidget.swift"),
            encoding: .utf8)) ?? ""
        XCTAssertTrue(src.contains("ControlWidget"), "控制中心入口必须声明")
        // 任务书原文断言 15.0，但 SDK swiftinterface 标注 ControlWidget 为
        // `@available(iOS 18.0, macOS 26.0, *)`——Mac 端 Controls 随 macOS
        // Tahoe 26 进入 Control Center，15 门控无法编译（macOS 15 上该 API
        // 不存在）。门控版本以 SDK 为准：26.0。15.0 断言系同代版本号误推。
        XCTAssertTrue(src.contains("#available(macOS 26.0"), "必须按 SDK 真实可用性门控（ControlWidget macOS 26.0+）")
    }
}
