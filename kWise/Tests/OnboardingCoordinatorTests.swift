// kWise/Tests/OnboardingCoordinatorTests.swift
//
// UX 重构 Phase 1 — onboarding step navigation: next/back/skip boundaries.
import XCTest
@testable import kWise

@MainActor
final class OnboardingCoordinatorTests: XCTestCase {

    func testInitialState() {
        let coordinator = OnboardingCoordinator()
        XCTAssertEqual(coordinator.currentPage, 0)
        XCTAssertEqual(coordinator.totalPages, 5)
    }

    func testNextAdvancesAndCompletes() {
        let coordinator = OnboardingCoordinator()
        var completed = false
        coordinator.onComplete = { completed = true }

        for _ in 0..<4 {
            coordinator.next()
        }
        XCTAssertEqual(coordinator.currentPage, 4)
        XCTAssertFalse(completed, "Completing fires only on the last page's next()")

        coordinator.next()
        XCTAssertTrue(completed)
    }

    func testBackDoesNotUnderflow() {
        let coordinator = OnboardingCoordinator()
        coordinator.back()
        XCTAssertEqual(coordinator.currentPage, 0, "back() on page 0 is a no-op")

        coordinator.next()
        coordinator.next()
        coordinator.back()
        XCTAssertEqual(coordinator.currentPage, 1)
    }

    func testSkipLandsOnLastPage() {
        let coordinator = OnboardingCoordinator()
        coordinator.skipFDA()
        XCTAssertEqual(coordinator.currentPage, coordinator.totalPages - 1)
    }
}
