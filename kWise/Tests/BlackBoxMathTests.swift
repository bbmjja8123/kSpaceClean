import XCTest
@testable import kWise

final class BlackBoxMathTests: XCTestCase {
    func testReconciledResidual() {
        let breakdown = BlackBoxMath.reconcile(usedBytes: 1_000, visibleBytes: 700, snapshotCount: 2)
        XCTAssertEqual(breakdown.residualBytes, 300)
        XCTAssertEqual(breakdown.status, .reconciled)
        XCTAssertEqual(breakdown.snapshotCount, 2)
    }

    func testNegativeResidualClampsToZeroAndFlags() {
        // 可见文件合计超过卷用量 = 采样口径问题（快照/硬链接/时差），绝不报负数。
        let breakdown = BlackBoxMath.reconcile(usedBytes: 100, visibleBytes: 700, snapshotCount: 0)
        XCTAssertEqual(breakdown.residualBytes, 0)
        XCTAssertEqual(breakdown.status, .negativeResidual)
    }

    func testMissingUsageIsInsufficientNotZero() {
        let breakdown = BlackBoxMath.reconcile(usedBytes: nil, visibleBytes: 700, snapshotCount: 1)
        XCTAssertEqual(breakdown.status, .insufficientData)
        XCTAssertEqual(breakdown.residualBytes, 0, "拿不到数据就出 0 = 编造，禁止")
        XCTAssertEqual(breakdown.usedBytes, nil)
    }
}
