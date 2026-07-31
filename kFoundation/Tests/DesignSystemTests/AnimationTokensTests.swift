import XCTest
import SwiftUI
@testable import DesignSystem

final class AnimationTokensTests: XCTestCase {
    func testDurationConstantsMatchCLAUDMD54() {
        XCTAssertEqual(KFAnimation.durationFast, 0.2)
        XCTAssertEqual(KFAnimation.durationNormal, 0.35)
        XCTAssertEqual(KFAnimation.durationSlow, 0.5)
    }

    func testScaleConstantsMatchCLAUDMD54() {
        XCTAssertEqual(KFAnimation.scaleTap, 0.97)
        XCTAssertEqual(KFAnimation.scaleHover, 1.02)
        XCTAssertEqual(KFAnimation.scaleInsert, 0.95)
    }

    func testEaseInOutFallbackExists() {
        _ = KFAnimation.easeInOut
    }

    func testSmoothAnimation() {
        // macOS 13 上 KFAnimation.smooth 不可用，仅在 14+ 断言其可求值。
        if #available(macOS 14.0, *) {
            _ = KFAnimation.smooth
        }
    }
}
