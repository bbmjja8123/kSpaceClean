// kWise/Tests/GraphFactoryRewiringTests.swift
//
// P3 M2/M5 重接入的 graph 装配锁定（镜像 PrivacyRehearsalChainTests 的
// privacyCleanupVM 工厂测试）：
// - appUninstallVM(onQuota:)：缓存复用 + onQuota 接进 VM（配额超限路由
//   买断墙 —— 卸载配额拒绝 ≠ 卸载成功的教训沿袭）；
// - startupItemsVM()：缓存复用 + 注入 graph 持有的 scope / persistence
//   （不再各自摸 AppScope.shared / PersistenceController.shared 默认值）。
import XCTest
@testable import kWise
import PowerScope

@MainActor
final class GraphFactoryRewiringTests: XCTestCase {

    func testAppUninstallFactoryCachesVMAndWiresQuotaCallback() {
        let graph = AppGraph()
        var fired = false
        let vm1 = graph.appUninstallVM { fired = true }
        let vm2 = graph.appUninstallVM { XCTFail("缓存复用 —— 二次工厂调用不得重接回调") }

        XCTAssertTrue(vm1 === vm2, "graph 缓存：两次装配同一 AppUninstallViewModel 实例")
        vm1.onQuotaExhausted?()
        XCTAssertTrue(fired, "onQuota 接线（配额超限路由买断墙）")
        // 引擎接线：工厂必须用 graph 的统一清理链，而非 VM 默认的
        // CleanupEngine.standard() 平行实例（预演/历史/回滚同一条链）。
        XCTAssertTrue(vm1.engine === graph.cleanupEngine,
                      "卸载走 graph.cleanupEngine（统一链）")
    }

    func testStartupItemsFactoryCachesVMAndInjectsGraphServices() throws {
        let graph = AppGraph()
        let vm1 = graph.startupItemsVM()
        let vm2 = graph.startupItemsVM()
        XCTAssertTrue(vm1 === vm2, "graph 缓存：两次装配同一 StartupItemsViewModel 实例")
        // scope 注入：VM 拿到的 provider 与 graph 持有的是同一动态类型
        // （MAS 下都是 AppScope 的 PowerScope actor；直营下同为
        // DirectScopeProvider）。existential 身份比较在 `any` 无类约束下
        // 不可用，这里锁动态类型 —— 真正的实例锁定由 scannerScope 注入点
        // （factory 传 graph.scope）保证。
        XCTAssertEqual(String(describing: type(of: vm1.scannerScope as Any)),
                       String(describing: type(of: graph.scope as Any)),
                       "启动项扫描使用 graph 持有的 scope provider（同类型）")
    }
}
