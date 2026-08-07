import XCTest
import SwiftUI
@testable import DesignSystem

final class StateModifierTests: XCTestCase {
    // MARK: - LoadingOverlayModifier

    func testLoadingOverlayDefaultConstructor() {
        let modifier = LoadingOverlayModifier(isLoading: true)
        XCTAssertTrue(modifier.isLoading)
        XCTAssertEqual(modifier.title, "Loading…")
        XCTAssertNil(modifier.progress)
    }

    func testLoadingOverlayCustomTitleAndProgress() {
        let modifier = LoadingOverlayModifier(
            isLoading: false,
            title: "Scanning…",
            progress: 0.42
        )
        XCTAssertFalse(modifier.isLoading)
        XCTAssertEqual(modifier.title, "Scanning…")
        XCTAssertEqual(modifier.progress, 0.42)
    }

    func testLoadingOverlayProgressBoundsAccepted() {
        // Accept any Double (the SwiftUI ProgressView will clamp visually).
        let zero = LoadingOverlayModifier(isLoading: true, progress: 0.0)
        let one = LoadingOverlayModifier(isLoading: true, progress: 1.0)
        XCTAssertEqual(zero.progress, 0.0)
        XCTAssertEqual(one.progress, 1.0)
    }

    // MARK: - EmptyStateModifier

    func testEmptyStateConstructorWithoutAction() {
        let modifier = EmptyStateModifier(
            isEmpty: true,
            iconName: "tray",
            title: "Nothing here",
            subtitle: "Add items to get started"
        )
        XCTAssertTrue(modifier.isEmpty)
        XCTAssertEqual(modifier.iconName, "tray")
        XCTAssertEqual(modifier.title, "Nothing here")
        XCTAssertEqual(modifier.subtitle, "Add items to get started")
        XCTAssertEqual(modifier.actionLabel, "Retry")
        XCTAssertNil(modifier.action)
    }

    func testEmptyStateConstructorWithAction() {
        var tapped = false
        let modifier = EmptyStateModifier(
            isEmpty: false,
            iconName: "wifi.slash",
            title: "Offline",
            subtitle: "Reconnect to refresh",
            actionLabel: "Reload",
            action: { tapped = true }
        )
        XCTAssertFalse(modifier.isEmpty)
        XCTAssertEqual(modifier.actionLabel, "Reload")
        modifier.action?()
        XCTAssertTrue(tapped)
    }

    func testEmptyStateActionCanBeInvokedMultipleTimes() {
        var count = 0
        let modifier = EmptyStateModifier(
            isEmpty: true,
            iconName: "circle",
            title: "T",
            subtitle: "S",
            actionLabel: "Go",
            action: { count += 1 }
        )
        modifier.action?()
        modifier.action?()
        XCTAssertEqual(count, 2)
    }

    // MARK: - ErrorStateModifier

    func testErrorStateConstructorWithMessageAndRetry() {
        let retryButton = Button("Retry Now") {}
        let modifier = ErrorStateModifier(
            message: "Connection failed",
            retryAction: retryButton
        )
        XCTAssertEqual(modifier.message, "Connection failed")
        XCTAssertNotNil(modifier.retryAction)
    }

    func testErrorStateConstructorWithoutMessage() {
        let modifier = ErrorStateModifier<EmptyView>(
            message: nil,
            retryAction: nil
        )
        XCTAssertNil(modifier.message)
        XCTAssertNil(modifier.retryAction)
    }

    // MARK: - View extension smoke tests
    //
    // The extensions return `some View`. Wrapping the result in `AnyView`
    // succeeds at runtime iff the extension returned a valid `View`.
    // We also exercise both `true` / `false` / `nil` parameter values.

    private struct ProbeView: View {
        var body: some View {
            Text("probe")
        }
    }

    @MainActor
    func testLoadingOverlayExtensionProducesAView() {
        let v: AnyView = AnyView(ProbeView().loadingOverlay(isLoading: true, title: "Go", progress: 0.1))
        XCTAssertNotNil(v)
    }

    @MainActor
    func testLoadingOverlayExtensionDefaults() {
        let v: AnyView = AnyView(ProbeView().loadingOverlay(isLoading: false))
        XCTAssertNotNil(v)
    }

    @MainActor
    func testEmptyStateExtensionProducesAView() {
        let v: AnyView = AnyView(ProbeView().emptyState(
            isEmpty: true,
            iconName: "tray",
            title: "Empty",
            subtitle: "Nothing to show",
            actionLabel: "Reload",
            action: {}
        ))
        XCTAssertNotNil(v)
    }

    @MainActor
    func testErrorStateExtensionWithoutRetryView() {
        let v: AnyView = AnyView(ProbeView().errorState(message: "Boom"))
        XCTAssertNotNil(v)
    }

    @MainActor
    func testErrorStateExtensionWithNilMessage() {
        let v: AnyView = AnyView(ProbeView().errorState(message: nil))
        XCTAssertNotNil(v)
    }

    @MainActor
    func testErrorStateExtensionWithRetryView() {
        let v: AnyView = AnyView(ProbeView().errorState(message: "Failed") {
            Button("Retry") {}
        })
        XCTAssertNotNil(v)
    }
}
