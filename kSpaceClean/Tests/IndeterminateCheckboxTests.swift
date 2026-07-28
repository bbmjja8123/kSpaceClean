import XCTest
import SwiftUI
@testable import kSpaceClean

final class IndeterminateCheckboxTests: XCTestCase {
    func test_allStatesCanConstructView() {
        _ = IndeterminateCheckbox(state: .off)
        _ = IndeterminateCheckbox(state: .on)
        _ = IndeterminateCheckbox(state: .mixed)
    }

    func test_defaultSizeUsesCheckboxToken() {
        let checkbox = IndeterminateCheckbox(state: .off)
        XCTAssertEqual(checkbox.size, RowSize.checkboxSize)
    }

    func test_customSizeIsPreserved() {
        let checkbox = IndeterminateCheckbox(state: .mixed, size: 24)
        XCTAssertEqual(checkbox.size, 24)
    }

    func test_checkStateAliasesMatchComponentStates() {
        XCTAssertEqual(CheckState.off, .unchecked)
        XCTAssertEqual(CheckState.on, .checked)
        XCTAssertNotEqual(CheckState.mixed, CheckState.off)
        XCTAssertNotEqual(CheckState.mixed, CheckState.on)
    }
}
