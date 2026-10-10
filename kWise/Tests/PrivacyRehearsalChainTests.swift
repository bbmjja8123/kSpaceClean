// kWise/Tests/PrivacyRehearsalChainTests.swift
//
// I5（P2 final）—— 隐私清理并入统一预演句式：选中项 → CleanupTarget →
// 预演 sheet（rehearsalItems）→ executeConfirmedCleanup（引擎 trash +
// 清理历史 + 回滚）。旧的 `PrivacyScanner.cleanup` 直删第二句式已删除。
// 真实临时文件（引擎 trash 语义无法 mock 掉文件系统），Core Data 走内存库。
import XCTest
@testable import kWise

@MainActor
final class PrivacyRehearsalChainTests: XCTestCase {

    private var root: URL!
    private var cacheFile: URL!
    private var cookieFile: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("privacy-rehearsal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        cacheFile = root.appendingPathComponent("cache.bin")
        cookieFile = root.appendingPathComponent("cookie.bin")
        try Data("x".utf8).write(to: cacheFile)
        try Data("x".utf8).write(to: cookieFile)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeViewModel() -> PrivacyViewModel {
        PrivacyViewModel(cleanupViewModel: CleanupViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true), quota: nil)))
    }

    func testPrepareRehearsalStagesTargetsAndTouchesNoFiles() async throws {
        let vm = makeViewModel()
        vm.items = [
            PrivacyItem(name: "缩略图缓存", category: .quickLook, url: cacheFile,
                        estimatedSize: 1),
            PrivacyItem(name: "Cookie", category: .safari, url: cookieFile,
                        estimatedSize: 1, isSelected: false, isLoginState: true),
        ]

        await vm.prepareRehearsal()

        let items = try XCTUnwrap(vm.rehearsalItems, "预演清单就绪（宿主据此呈现 sheet）")
        XCTAssertEqual(items.map(\.target.url), [cacheFile],
                       "预演 = 选中项 1:1；未选中的登录态文件不进预演")
        XCTAssertEqual(items.first?.target.risk, .recommended)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path),
                      "预演段不动任何文件")
        XCTAssertTrue(FileManager.default.fileExists(atPath: cookieFile.path))
    }

    func testConfirmRehearsalExecutesViaUnifiedChain() async throws {
        let vm = makeViewModel()
        vm.items = [
            PrivacyItem(name: "缩略图缓存", category: .quickLook, url: cacheFile,
                        estimatedSize: 1),
        ]
        await vm.prepareRehearsal()
        let items = try XCTUnwrap(vm.rehearsalItems)

        await vm.confirmRehearsal(items.map(\.target))

        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path),
                       "确认 → 统一链执行（引擎 trash）")
        XCTAssertNil(vm.rehearsalItems, "清单消费即作废")
        XCTAssertTrue(vm.items.isEmpty, "成功项从列表移除")
        XCTAssertNotNil(vm.statusMessage)
    }

    func testCancelRehearsalLeavesFilesUntouched() async throws {
        let vm = makeViewModel()
        vm.items = [
            PrivacyItem(name: "缩略图缓存", category: .quickLook, url: cacheFile,
                        estimatedSize: 1),
        ]
        await vm.prepareRehearsal()
        XCTAssertNotNil(vm.rehearsalItems)

        vm.cancelRehearsal()

        XCTAssertNil(vm.rehearsalItems)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path),
                      "取消即作废 —— 绝不执行")
    }
}
