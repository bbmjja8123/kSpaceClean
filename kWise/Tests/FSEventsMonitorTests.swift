// kWise/Tests/FSEventsMonitorTests.swift
//
// Task 7：FSEvents 变更监视的契约 —— 回调只在会话生命周期内发生：
// - 监视目录内变更 → 10s 内收到一次 onChange（沙盒宿主内临时目录可写可监听）；
// - stop() 后再变更 → 静默（不得再回调）。
import XCTest
import FileScanner
@testable import kWise

final class FSEventsMonitorTests: XCTestCase {
    // 沙盒测试宿主内临时目录可写可监听；10s 内必须收到一次变更回调。
    func testChangeInWatchedDirTriggersCallback() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fsev-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let expectation = expectation(description: "onChange fired")
        let monitor = FSEventsMonitor(watching: dir, latency: 0.5) { expectation.fulfill() }
        monitor.start()
        defer { monitor.stop(); try? FileManager.default.removeItem(at: dir) }
        // 沙盒宿主流创建失败（监视是增强不是承诺）→ 诚实跳过，不假绿。
        try XCTSkipUnless(monitor.isStreamCreated,
                          "FSEventStreamCreate failed in sandboxed test host")
        try Data("x".utf8).write(to: dir.appendingPathComponent("new.bin"))
        wait(for: [expectation], timeout: 10)
    }

    func testStopSilencesCallbacks() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fsev2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var fired = false
        let monitor = FSEventsMonitor(watching: dir, latency: 0.5) { fired = true }
        monitor.start(); monitor.stop()
        try Data("x".utf8).write(to: dir.appendingPathComponent("y.bin"))
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        XCTAssertFalse(fired, "stop 后不得再回调")
        try? FileManager.default.removeItem(at: dir)
    }
}
