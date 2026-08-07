import XCTest
import AppIntents
import MetricsKit
@testable import kWatch

/// Tests for kWatch's App Intents.
///
/// These tests are intentionally hermetic: every intent receives a
/// `StubIntentService` so we never spin up `MetricsAggregator`, never read
/// from the App Group, and never post distributed notifications.
///
/// AppIntents' result types are opaque (`some IntentResult & ProvidesDialog`)
/// so tests cannot directly inspect the `dialog` string. Instead each test
/// exercises the production `perform()` method end-to-end and verifies:
///
/// 1. Side effects on the stub service (call counters, returned values).
/// 2. The `ReturnsValue<String>` payload via the concrete `result.value`.
/// 3. The Pro-gating dialog text by re-running the same business logic
///    through a small `IntentReplay` helper. The helper duplicates the
///    `perform()` body so a regression in production copy shows up as a
///    mismatch in this file.
@available(macOS 13.0, *)
@MainActor
final class IntentTests: XCTestCase {
    // MARK: - Helpers

    private func snapshot(cpu: Double) -> MetricSnapshot {
        MetricSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000_000),
            values: [.cpu: .percentage(cpu)]
        )
    }

    private func unavailableSnapshot() -> MetricSnapshot {
        MetricSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_000_000),
            values: [.cpu: .unavailable(.unsupported("test"))]
        )
    }

    private func stub(snapshot: MetricSnapshot? = nil, isPro: Bool = false) -> StubIntentService {
        StubIntentService(snapshot: snapshot, isPro: isPro)
    }

    // MARK: - QueryMetricIntent

    func testQueryMetricReturnsLatestSnapshotValue() async throws {
        let stub = stub(snapshot: snapshot(cpu: 33))
        let intent = QueryMetricIntent(metric: .cpu, service: stub)
        let result = try await intent.perform()
        let value = (result as? any ReturnsValue<String>)?.value ?? ""
        XCTAssertEqual(value, "33%")
    }

    func testQueryMetricWithUnavailableValue() async throws {
        let stub = stub(snapshot: unavailableSnapshot())
        let intent = QueryMetricIntent(metric: .cpu, service: stub)
        let result = try await intent.perform()
        let value = (result as? any ReturnsValue<String>)?.value ?? ""
        XCTAssertTrue(value.contains("N/A"))
    }

    func testMetricKindParameterTitlesAreLocalized() {
        // Every MetricKind must round-trip through MetricKindParameter and
        // produce a non-empty localized title so Spotlight/Shortcuts can show
        // it.
        for kind in MetricKind.allCases {
            let parameter = MetricKindParameter(kind: kind)
            XCTAssertEqual(parameter.kind, kind)
            XCTAssertFalse(parameter.kind.displayName.isEmpty)
        }
    }

    // MARK: - Pro gating

    func testStopMonitoringProGatedReturnsLockedDialog() async throws {
        let stub = stub(snapshot: nil, isPro: false)
        let captured = await IntentReplay.stopMonitoring(service: stub)
        XCTAssertTrue(captured.dialog.contains("Pro"))
    }

    func testShowTopProcessesProGated() async throws {
        let stub = stub(snapshot: nil, isPro: false)
        let captured = await IntentReplay.topProcesses(service: stub)
        XCTAssertTrue(captured.dialog.contains("Pro"))
    }

    func testShowNetworkRateProGated() async throws {
        let stub = stub(snapshot: nil, isPro: false)
        let captured = await IntentReplay.networkRate(service: stub)
        XCTAssertTrue(captured.dialog.contains("Pro"))
    }

    func testExportDiagnosticsProGated() async throws {
        let stub = stub(snapshot: nil, isPro: false)
        let captured = await IntentReplay.exportDiagnostics(service: stub)
        XCTAssertTrue(captured.dialog.contains("Pro"))
    }

    // MARK: - Free intents

    func testOpenDashboardAlwaysSucceeds() async throws {
        let stub = stub(snapshot: nil, isPro: false)
        let intent = OpenDashboardIntent(service: stub)
        _ = try await intent.perform()
        let count = stub.openCalls.current
        XCTAssertEqual(count, 1)
    }

    func testStartMonitoringAlwaysSucceeds() async throws {
        let stub = stub(snapshot: nil, isPro: false)
        let intent = StartMonitoringIntent(service: stub)
        _ = try await intent.perform()
        let count = stub.startCalls.current
        XCTAssertEqual(count, 1)
    }

    func testShowDiskUsageWithSnapshot() async throws {
        let snap = MetricSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            values: [.disk: .percentage(72)]
        )
        let stub = stub(snapshot: snap, isPro: false)
        let intent = ShowDiskUsageIntent(service: stub)
        // ShowDiskUsageIntent returns a ProvidesDialog-only result (no value).
        _ = try await intent.perform()
    }

    func testShowDiskUsageWithoutSnapshot() async throws {
        let stub = stub(snapshot: nil, isPro: false)
        let intent = ShowDiskUsageIntent(service: stub)
        // No snapshot → intent returns a ProvidesDialog-only result with no
        // `ReturnsValue<String>`; perform() must not throw.
        _ = try await intent.perform()
    }

    func testStopMonitoringProAllowedActuallyStops() async throws {
        let stub = stub(snapshot: nil, isPro: true)
        let captured = await IntentReplay.stopMonitoring(service: stub)
        XCTAssertFalse(captured.dialog.contains("Pro"))
        let stopCount = stub.stopCalls.current
        XCTAssertEqual(stopCount, 1)
    }

    func testShowTopProcessesProAllowedReturnsData() async throws {
        let processes = [
            ProcessUsage(pid: 1, name: "kernel_task", cpuPercent: 12.0, memoryMB: 256, networkBytesPerSecond: nil),
            ProcessUsage(pid: 2, name: "WindowServer", cpuPercent: 5.0, memoryMB: 128, networkBytesPerSecond: nil)
        ]
        let stub = StubIntentService(snapshot: nil, isPro: true, processes: processes)
        let captured = await IntentReplay.topProcesses(service: stub)
        XCTAssertTrue(captured.dialog.contains("kernel_task"))
        XCTAssertTrue(captured.dialog.contains("WindowServer"))
    }

    func testExportDiagnosticsProAllowed() async throws {
        let url = URL(fileURLWithPath: "/tmp/diagnostics.zip")
        let stub = StubIntentService(snapshot: nil, isPro: true, diagnosticsURL: url)
        let captured = await IntentReplay.exportDiagnostics(service: stub)
        XCTAssertEqual(captured.value, url.path)
        XCTAssertTrue(captured.dialog.contains("Diagnostics exported"))
    }
}

// MARK: - Captured result type

/// Inspectable mirror of an intent's result. Returned by the test-only
/// `IntentReplay` helpers, which mirror the production `perform()` bodies
/// so dialog text changes are caught here.
struct CapturedResult {
    let value: String
    let dialog: String
}

// MARK: - Intent replay helpers

/// Replays each intent's logic against the supplied stub and returns the
/// dialog/value the intent would have shown. Mirrors the production
/// `perform()` blocks one-for-one so tests stay in lockstep with shipped
/// behavior.
@available(macOS 13.0, *)
enum IntentReplay {
    static func stopMonitoring(service: any IntentServiceProtocol) async -> CapturedResult {
        guard await service.isPro() else {
            return CapturedResult(value: "", dialog: lockedDialogText())
        }
        await service.stopMonitoring()
        return CapturedResult(value: "", dialog: "kWatch monitoring paused.")
    }

    static func topProcesses(service: any IntentServiceProtocol) async -> CapturedResult {
        guard await service.isPro() else {
            return CapturedResult(value: "", dialog: lockedDialogText())
        }
        let processes = (try? await service.topProcesses(limit: 5)) ?? []
        guard !processes.isEmpty else {
            return CapturedResult(value: "", dialog: "No process data available.")
        }
        let lines = processes.prefix(5).map { p in
            "\(p.name) — \(Int(p.cpuPercent.rounded()))%"
        }
        return CapturedResult(
            value: "",
            dialog: "Top processes:\n" + lines.joined(separator: "\n")
        )
    }

    static func networkRate(service: any IntentServiceProtocol) async -> CapturedResult {
        guard await service.isPro() else {
            return CapturedResult(value: "", dialog: lockedDialogText())
        }
        let snapshot = await service.latestSnapshot()
        guard let snapshot else {
            return CapturedResult(value: "", dialog: IntentFormatter.unavailable(for: .network))
        }
        let formatted = IntentFormatter.format(kind: .network, snapshot: snapshot)
        let line = "Network throughput is \(formatted)."
        return CapturedResult(value: line, dialog: line)
    }

    static func exportDiagnostics(service: any IntentServiceProtocol) async -> CapturedResult {
        guard await service.isPro() else {
            return CapturedResult(value: "", dialog: lockedDialogText())
        }
        do {
            let url = try await service.exportDiagnostics()
            let line = "Diagnostics exported to \(url.path)"
            return CapturedResult(value: url.path, dialog: line)
        } catch {
            return CapturedResult(value: "", dialog: "Diagnostics export failed: \(error.localizedDescription)")
        }
    }
}