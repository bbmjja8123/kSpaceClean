// kWise/Tests/ScanScopeContractTests.swift
//
// P3 双渠道 — 扫描范围契约（kWise/docs/Launch/MasScanScope.md）的机器钉。
//
// 任何破坏「直营版全可读 / MAS 版受限必现于 restrictedPaths / 授权门控
// 三档语义」的改动都会在这里红。

import XCTest
@testable import kWise
import PowerScope

final class ScanScopeContractTests: XCTestCase {

    // MARK: - ScopeLevel.fullAccess（直营版第三档）

    func testFullAccessCanReadEveryURL() {
        let capability = ScopeCapability(level: .fullAccess)
        let probes = [
            URL(fileURLWithPath: "/private/var/log"),
            URL(fileURLWithPath: "/Library"),
            URL(fileURLWithPath: "/Users/someone/Library/Mail"),
            URL(fileURLWithPath: "/Volumes/External/Deep/Nested"),
        ]
        for url in probes {
            XCTAssertTrue(capability.canRead(url), "fullAccess 必须可读 \(url.path)")
        }
    }

    func testFullAccessRanksAboveOtherLevels() {
        XCTAssertLessThan(ScopeLevel.containerOnly, .homeGranted)
        XCTAssertLessThan(ScopeLevel.homeGranted, .fullAccess)
    }

    // MARK: - DirectScopeProvider（直营版授权流程是 no-op）

    func testDirectScopeProviderReportsFullAccess() async {
        let provider = DirectScopeProvider()
        let capability = await provider.capability()
        XCTAssertEqual(capability.level, .fullAccess)
        XCTAssertNil(capability.grantedRoot)
    }

    func testDirectScopeProviderGrantIsNoOpReturningFullAccess() async {
        let provider = DirectScopeProvider()
        do {
            let capability = try await provider.grantHomeFolder()
            XCTAssertEqual(capability.level, .fullAccess, "直营版授权必须是无操作，不得触发任何面板/书签流程")
        } catch {
            XCTFail("grantHomeFolder 在直营版不得抛错: \(error)")
        }
        await provider.revoke() // 不得崩溃/不得降级
        let after = await provider.capability()
        XCTAssertEqual(after.level, .fullAccess, "revoke 后直营版仍是全访问")
    }

    func testDirectScopeProviderWithAccessRunsBodyDirectly() async throws {
        let provider = DirectScopeProvider()
        let url = URL(fileURLWithPath: "/tmp")
        let marker = try await provider.withAccess(url) { inner in inner }
        XCTAssertEqual(marker, url, "withAccess 必须原样执行 body（无 security scope 包装）")
    }

    // MARK: - QuickCleanGate 三档语义

    func testQuickCleanGateAllowsFullAccessPipeline() {
        XCTAssertTrue(QuickCleanGate.allowsPipeline(.fullAccess), "直营版快捷回收必须放行")
        XCTAssertTrue(QuickCleanGate.allowsPipeline(.homeGranted))
        XCTAssertFalse(QuickCleanGate.allowsPipeline(.containerOnly))
    }

    func testQuickCleanGateGrantCardOnlyForContainerOnly() {
        XCTAssertFalse(QuickCleanGate.showsGrantCard(.fullAccess), "直营版 hero 不得渲染授权卡")
        XCTAssertFalse(QuickCleanGate.showsGrantCard(.homeGranted))
        XCTAssertTrue(QuickCleanGate.showsGrantCard(.containerOnly))
    }

    // MARK: - 渠道检测（测试宿主 = MAS target，编译条件 DISTRIBUTION_MAS）

    func testDistributionChannelResolvesToMASInTestHost() {
        // 测试宿主是 kWise（MAS）target 编译的 —— 该断言同时验证
        // DISTRIBUTION_MAS 编译条件确实打进了 target（漏打则红）。
        XCTAssertEqual(DistributionChannel.current, .macAppStore)
        XCTAssertTrue(DistributionChannel.isSandboxed)
    }

    // MARK: - 类目根 vs 范围（MasScanScope.md §「三层可读性」）

    func testAllDefaultCategoryRootsReadableUnderFullAccess() async {
        // 直营版：每个默认类目根都必须被判为可读 —— fullAccess 漏判即红。
        let capability = await DirectScopeProvider().capability()
        for definition in CategoryDefinition.defaults {
            for path in definition.paths {
                let resolved = UserPathResolver.expandTilde(path)
                let url = URL(fileURLWithPath: resolved)
                XCTAssertTrue(capability.canRead(url),
                              "直营版必须可读 \(definition.id) 根 \(resolved)")
            }
        }
    }

    func testContainerOnlyWithoutGrantReadsNoDefaultRoot() {
        // MAS 未授权：空 capability（containerOnly、无公共目录探得）下
        // 所有默认根都必须不可读 —— 这是「未授权即授权引导态」契约
        // （needsFullDiskAccess fast-fail）与 restrictedPaths 跳过区的
        // 前提。任何一个根"碰巧可读"都会让空扫被误归因为干净 Mac。
        let capability = ScopeCapability(level: .containerOnly)
        for definition in CategoryDefinition.defaults {
            for path in definition.paths {
                let resolved = UserPathResolver.expandTilde(path)
                let url = URL(fileURLWithPath: resolved)
                XCTAssertFalse(capability.canRead(url),
                               "未授权时 \(definition.id) 根 \(resolved) 不得被 containerOnly capability 放行")
            }
        }
    }
}
