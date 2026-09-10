// kWise/App/AppDelegate.swift
//
// 退出守卫 (v2.6)：修复"程序退出时 crash"。
//
// 根因：退出时 SwiftUI/AppKit 开始拆除运行循环，而 Core Data 的
// main context 上仍挂着 `_processRecentChanges` 的 runloop observer
// （pending insertions/deletions），后台 transient context 也可能在
// default-qos 队列上被释放 —— 两者的析构与 runtime teardown 竞争，
// 落到 `lookUpImpOrForward` 读到已释放内存（SIGSEGV，崩溃报告
// kWise-2026-09-05 与用户"退出时 crash"一致）。
//
// 修复：applicationShouldTerminate 里同步保存 + 清空 main context 的
// pending changes，并停掉菜单栏刷新 timer，让拆除过程没有遗留工作。
import AppKit
import CoreData

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 1) 停菜单栏刷新 timer（避免拆除期间 timer 回调触碰已释放状态）。
        MenuBarManager.shared?.stopRefreshTimer()

        // 2) 同步保存 main context 并处理 pending changes —— 把
        //    `_processRecentChanges` 的挂起工作在拆除前做完。
        let context = PersistenceController.shared.viewContext
        context.performAndWait {
            if context.hasChanges {
                do { try context.save() }
                catch { Log.ui.error("[Quit] final save failed: \(error)") }
            }
            context.processPendingChanges()
            context.reset()
        }

        return .terminateNow
    }
}
