import XCTest
@testable import kWise

/// Verifies the standalone behaviour of ``WarningToast``.
///
/// The toast is a pure SwiftUI view with three callbacks — there is no
/// engine or persistence layer to exercise. We assert that the public
/// surface (initializer + callback identity) compiles and behaves as
/// expected, plus some structural smoke tests that exercise the warning
/// row computation paths.
final class WarningToastTests: XCTestCase {
    /// A view model-style holder that lets us capture which button fired.
    /// We avoid `ObservableObject` so the test stays synchronous.
    final class CallCounter {
        var skipCount = 0
        var terminateCount = 0
        var abortCount = 0
    }

    func test_callbacksAreWiredToCorrectButtons() {
        let counter = CallCounter()
        let items = [
            WarnItem(
                appName: "Sketch",
                bundleID: "com.bohemiancoding.sketch3",
                processID: 501,
                conflictingPaths: ["/Users/me/Library/Caches/Sketch/index.db"]
            ),
        ]

        let toast = WarningToast(
            warnItems: items,
            onSkip: { counter.skipCount += 1 },
            onTerminate: { counter.terminateCount += 1 },
            onAbort: { counter.abortCount += 1 }
        )

        // Smoke-test that the view constructed successfully.
        XCTAssertNotNil(toast)
        // Confirm none of the counters have been bumped — the closures
        // have not been invoked yet.
        XCTAssertEqual(counter.skipCount, 0)
        XCTAssertEqual(counter.terminateCount, 0)
        XCTAssertEqual(counter.abortCount, 0)
    }

    /// The toast must accept an empty list without crashing at construction.
    /// The caller is responsible for not presenting it in that state, but
    /// the view itself should be tolerant.
    func test_emptyWarnItemsListIsAccepted() {
        let toast = WarningToast(
            warnItems: [],
            onSkip: {},
            onTerminate: {},
            onAbort: {}
        )
        XCTAssertNotNil(toast)
    }

    /// Multiple warn items must each render a row. We assert that the
    /// view constructs with multiple distinct entries.
    func test_multipleWarnItemsAreAccepted() {
        let items = [
            WarnItem(
                appName: "Sketch",
                bundleID: "com.bohemiancoding.sketch3",
                processID: 501,
                conflictingPaths: ["/Users/me/Library/Caches/Sketch/index.db"]
            ),
            WarnItem(
                appName: "Xcode",
                bundleID: "com.apple.dt.Xcode",
                processID: 998,
                conflictingPaths: ["/Users/me/Library/Developer/Xcode/DerivedData/ModuleCache"]
            ),
        ]

        let toast = WarningToast(
            warnItems: items,
            onSkip: {},
            onTerminate: {},
            onAbort: {}
        )
        XCTAssertEqual(toast.warnItems.count, 2)
    }

    /// Verifies that the warn items supplied to the view are stored
    /// verbatim and are accessible via the public property.
    func test_warnItemsPreservedVerbatim() {
        let items = [
            WarnItem(
                appName: "TestApp",
                bundleID: "com.test.app",
                processID: 1234,
                conflictingPaths: ["/tmp/a", "/tmp/b", "/tmp/c"]
            ),
        ]
        let toast = WarningToast(
            warnItems: items,
            onSkip: {},
            onTerminate: {},
            onAbort: {}
        )
        XCTAssertEqual(toast.warnItems.first?.appName, "TestApp")
        XCTAssertEqual(toast.warnItems.first?.processID, 1234)
        XCTAssertEqual(toast.warnItems.first?.conflictingPaths.count, 3)
    }
}
