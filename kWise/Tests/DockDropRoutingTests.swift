// kWise/Tests/DockDropRoutingTests.swift
//
// Task 5（feature sprint）：Dock 图标拖放粉碎的路由链。
//
// Dock 拖放 → NSApplicationDelegate `application(_:open:)` →
// `Notification.Name.klarisOpenFiles` → RootView `.onReceive` →
// `DragToShredModel.urlsDropped`（既有全有全无校验，与整窗拖放同语义）。
// 另钉 Info.plist 必须声明 CFBundleDocumentTypes——没有它 open 事件
// 根本不会进 AppDelegate，Dock 拖放目标不出现。
import XCTest
import AppKit
@testable import kWise

// DragToShredModel 是 @MainActor —— 通知投递断言须在主 actor 上跑。
@MainActor
final class DockDropRoutingTests: XCTestCase {
    // Dock 拖放 → AppDelegate open → 通知 → DragToShredModel 全有全无。
    func testOpenNotificationFeedsDragToShredModel() {
        let model = DragToShredModel()
        var received: [URL] = []
        model.onShredRequested = { received = $0 }

        let regular = FileManager.default.temporaryDirectory
            .appendingPathComponent("dock-\(UUID().uuidString).txt")
        try? Data("x".utf8).write(to: regular)

        NotificationCenter.default.post(
            name: .klarisOpenFiles, object: nil,
            userInfo: ["urls": [regular]])
        XCTAssertEqual(received.map(\.lastPathComponent), [regular.lastPathComponent])

        // 目录混入 → 整批拒绝（与整窗拖放同语义）。
        received = []
        NotificationCenter.default.post(
            name: .klarisOpenFiles, object: nil,
            userInfo: ["urls": [regular, FileManager.default.temporaryDirectory]])
        XCTAssertTrue(received.isEmpty)

        try? FileManager.default.removeItem(at: regular)
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
