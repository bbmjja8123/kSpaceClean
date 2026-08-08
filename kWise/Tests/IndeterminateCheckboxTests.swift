import XCTest
import SwiftUI
@testable import kWise

@MainActor
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

    // MARK: - Rendered semantics

    /// `.on` state must render a `checkmark` SF Symbol and announce "已勾选".
    func test_onStateRendersCheckmarkAndLabel() {
        let checkbox = IndeterminateCheckbox(state: .on)
        XCTAssertEqual(checkbox.symbolName(for: .on), "checkmark")
        XCTAssertEqual(checkbox.accessibilityLabelText(for: .on), "已勾选")
    }

    /// `.mixed` state must render a `minus` SF Symbol and announce "部分勾选".
    func test_mixedStateRendersMinusAndLabel() {
        let checkbox = IndeterminateCheckbox(state: .mixed)
        XCTAssertEqual(checkbox.symbolName(for: .mixed), "minus")
        XCTAssertEqual(checkbox.accessibilityLabelText(for: .mixed), "部分勾选")
    }

    /// `.off` state must render no SF Symbol and announce "未勾选".
    func test_offStateRendersNoSymbolAndLabel() {
        let checkbox = IndeterminateCheckbox(state: .off)
        XCTAssertNil(checkbox.symbolName(for: .off), ".off must not render any SF Symbol")
        XCTAssertEqual(checkbox.accessibilityLabelText(for: .off), "未勾选")
    }

    /// The CheckState.unchecked / .checked aliases must produce the same
    /// symbol/label mappings as their `.off` / `.on` counterparts — this
    /// guards the A4 alias contract from regressing.
    func test_uncheckedAndCheckedAliasesAnnounceSameLabels() {
        let checkbox = IndeterminateCheckbox(state: .off)
        XCTAssertEqual(
            checkbox.symbolName(for: .unchecked),
            checkbox.symbolName(for: .off)
        )
        XCTAssertEqual(
            checkbox.symbolName(for: .checked),
            checkbox.symbolName(for: .on)
        )
        XCTAssertEqual(
            checkbox.accessibilityLabelText(for: .unchecked),
            checkbox.accessibilityLabelText(for: .off)
        )
        XCTAssertEqual(
            checkbox.accessibilityLabelText(for: .checked),
            checkbox.accessibilityLabelText(for: .on)
        )
    }

    /// Every state mapping must produce a distinct accessibility label —
    /// if two states collapsed onto the same label, VoiceOver users would
    /// hear the wrong spoken text for the rendered selection.
    func test_accessibilityLabelsAreUniqueAcrossStates() {
        let checkbox = IndeterminateCheckbox(state: .off)
        let labels = Set([
            checkbox.accessibilityLabelText(for: .off),
            checkbox.accessibilityLabelText(for: .on),
            checkbox.accessibilityLabelText(for: .mixed)
        ])
        XCTAssertEqual(labels.count, 3, "expected 3 distinct labels, got \(labels)")
    }
}