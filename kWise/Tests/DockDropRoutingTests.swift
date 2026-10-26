// kWise/Tests/DockDropRoutingTests.swift
//
// Task 5（feature sprint）：Dock 图标拖放粉碎的路由链。
//
// Dock 拖放 → NSApplicationDelegate `application(_:open:)` →
// `Notification.Name.klarisOpenFiles` → RootView `.onReceive` →
// `DragToShredModel.urlsDropped`（既有全有全无校验，与整窗拖放同语义）。
// 另钉 Info.plist 必须声明 CFBundleDocumentTypes——没有它 open 事件
// 根本不会进 AppDelegate，Dock 拖放目标不出现。
//
// 链路中间的 RootView 一跳是 SwiftUI `.onReceive`——单测环境没有挂载的
// 场景，直接 post 通知到不了模型（2026-10-27 全量基线实证，原断言按整链
// 写法确定性落空）。所以按链路逐跳验证：AppDelegate 转发与模型末端
// 运行时真跑，RootView 接线用源码审计钉住（与 SurfaceRetirementAuditTests
// 同源做法）；真实端到端行为归 GUI 冒烟。
import XCTest
import AppKit
@testable import kWise

// DragToShredModel 是 @MainActor —— 相关断言须在主 actor 上跑。
@MainActor
final class DockDropRoutingTests: XCTestCase {
    // 跳 1：AppDelegate 收到 open 事件 → 以 `.klarisOpenFiles` 广播 urls。
    func testAppDelegateOpenPostsKlarisOpenFiles() {
        let regular = FileManager.default.temporaryDirectory
            .appendingPathComponent("dock-\(UUID().uuidString).txt")
        try? Data("x".utf8).write(to: regular)
        defer { try? FileManager.default.removeItem(at: regular) }

        let delivered = expectation(description: "klarisOpenFiles delivered")
        let observer = NotificationCenter.default.addObserver(
            forName: .klarisOpenFiles, object: nil, queue: .main
        ) { note in
            XCTAssertEqual(note.userInfo?["urls"] as? [URL], [regular])
            delivered.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        AppDelegate().application(NSApplication.shared, open: [regular])
        wait(for: [delivered], timeout: 2)
    }

    // 跳 2：RootView 把 `.klarisOpenFiles` 接到同一 DragToShredModel
    // （源码审计——SwiftUI `.onReceive` 在单测宿主无场景可挂载）。
    func testRootViewRoutesNotificationToDragToShredModel() throws {
        let rootView = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .appendingPathComponent("../App/RootView.swift")
        let source = try String(contentsOf: rootView, encoding: .utf8)
        XCTAssertTrue(source.contains(
            "NotificationCenter.default.publisher(for: .klarisOpenFiles)"),
            "RootView 必须订阅 .klarisOpenFiles（Dock 拖放路由中段）")
        XCTAssertTrue(source.contains("dragToShred.urlsDropped"),
            "RootView 必须把通知转发给 DragToShredModel.urlsDropped（全有全无末端）")
    }

    // 跳 3（末端）：DragToShredModel 全有全无 —— 普通文件转发，目录混入整批拒绝。
    func testDragToShredModelAllOrNothing() {
        let model = DragToShredModel()
        var received: [URL] = []
        model.onShredRequested = { received = $0 }

        let regular = FileManager.default.temporaryDirectory
            .appendingPathComponent("dock-\(UUID().uuidString).txt")
        try? Data("x".utf8).write(to: regular)
        defer { try? FileManager.default.removeItem(at: regular) }

        XCTAssertTrue(model.urlsDropped([regular]))
        XCTAssertEqual(received, [regular])

        // 目录混入 → 整批拒绝（与整窗拖放同语义）。
        received = []
        XCTAssertFalse(model.urlsDropped([regular, FileManager.default.temporaryDirectory]))
        XCTAssertTrue(received.isEmpty)
    }

    func testInfoPlistDeclaresDocumentTypes() throws {
        // Dock 拖放目标需要 CFBundleDocumentTypes；没有它 open 事件不进 AppDelegate。
        let plist = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../Info.plist")
        let data = try Data(contentsOf: plist)
        let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let types = dict?["CFBundleDocumentTypes"] as? [[String: Any]]
        XCTAssertNotNil(types)
        let contentTypes = types?.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] } ?? []
        XCTAssertTrue(contentTypes.contains("public.data"))
        XCTAssertTrue(contentTypes.contains("public.folder"))
    }
}
