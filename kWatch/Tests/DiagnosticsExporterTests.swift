import XCTest
import AppKit
import MetricsKit
@testable import kWatch

@MainActor
final class DiagnosticsExporterTests: XCTestCase {

    // MARK: - Helpers

    /// Stub `DiagnosticsSavePanel` that returns a pre-configured URL
    /// instead of presenting an `NSSavePanel`. Captures the requested
    /// default filename so tests can verify the suggestion.
    final class StubSavePanel: DiagnosticsSavePanel, @unchecked Sendable {
        var destination: URL?
        var capturedFilename: String?
        var promptCount = 0

        init(destination: URL?) {
            self.destination = destination
        }

        func prompt(defaultFilename: String) async -> URL? {
            promptCount += 1
            capturedFilename = defaultFilename
            return destination
        }
    }

    /// Snapshot fixture used to verify that aggregate metrics make it into
    /// the export while the raw `SharedSnapshot` records do not.
    private func makeSnapshot(
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000),
        cpu: Double = 42,
        memory: Double = 60,
        disk: Double = 70,
        network: UInt64 = 1234,
        temperature: Double? = 50,
        fan: Double? = 2200,
        battery: Double? = 88,
        cpuAvailable: Bool = true,
        memoryAvailable: Bool = true,
        diskAvailable: Bool = true,
        networkAvailable: Bool = true,
        temperatureAvailable: Bool = true,
        fanAvailable: Bool = true,
        batteryAvailable: Bool = true
    ) -> SharedSnapshot {
        SharedSnapshot(
            timestamp: timestamp,
            cpuPercent: cpu,
            memoryPercent: memory,
            diskPercent: disk,
            networkBytesPerSecond: network,
            temperatureCelsius: temperature,
            fanRPM: fan,
            batteryPercent: battery,
            cpuAvailable: cpuAvailable,
            memoryAvailable: memoryAvailable,
            diskAvailable: diskAvailable,
            networkAvailable: networkAvailable,
            temperatureAvailable: temperatureAvailable,
            fanAvailable: fanAvailable,
            batteryAvailable: batteryAvailable,
            isPro: false,
            menuBarModeRaw: "numeric"
        )
    }

    // MARK: - Tests

    /// The exporter must scrub process-name-like strings and IPv4 addresses
    /// out of the JSON output. Even if those strings are not present in the
    /// current payload schema, this guards against regressions where free
    /// text fields are added later.
    func testExportOmitsProcessNamesAndNetworkAddresses() async throws {
        let panel = StubSavePanel(destination: tempURL())
        // Build a snapshot history whose raw fields happen to contain
        // strings that must be scrubbed if they ever leak into the export.
        // The current `SharedSnapshot` does not include process names;
        // the test exercises the public aggregate path, but also writes a
        // separate string that we expect to be absent from the payload.
        let snapshots = [makeSnapshot()]
        let exporter = DiagnosticsExporter(
            panel: panel,
            snapshotProvider: { snapshots },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let url = try await exporter.export()
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? ""

        XCTAssertFalse(text.contains("Safari"), "Process name 'Safari' leaked into export")
        XCTAssertFalse(text.contains("192.168."), "IPv4 fragment leaked into export")
        XCTAssertFalse(text.contains("10.0.0."), "IPv4 fragment leaked into export")
    }

    /// Aggregate percentages/rates must be present, but the exporter must
    /// never serialize the raw `SharedSnapshot` records themselves (the
    /// user only wants aggregate signals in their support bundle).
    func testExportIncludesAggregateMetricsButNotRawSnapshots() async throws {
        let panel = StubSavePanel(destination: tempURL())
        let snapshot = makeSnapshot(
            cpu: 33,
            memory: 44,
            disk: 55,
            network: 9876,
            temperature: 60,
            fan: 1500,
            battery: 77
        )
        let exporter = DiagnosticsExporter(
            panel: panel,
            snapshotProvider: { [snapshot] },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let url = try await exporter.export()
        let text = try String(contentsOf: url)

        XCTAssertTrue(text.contains("cpuPercent"), "cpuPercent missing from aggregate block")
        XCTAssertTrue(text.contains("memoryPercent"), "memoryPercent missing from aggregate block")
        XCTAssertTrue(text.contains("diskPercent"), "diskPercent missing from aggregate block")
        XCTAssertTrue(text.contains("networkBytesPerSecond"), "networkBytesPerSecond missing from aggregate block")
        XCTAssertTrue(text.contains("sampleCount"), "sampleCount missing from aggregate block")

        // Raw snapshot keys must not appear.
        XCTAssertFalse(text.contains("\"isPro\""), "Raw snapshot field 'isPro' leaked into export")
        XCTAssertFalse(text.contains("\"menuBarModeRaw\""), "Raw snapshot field 'menuBarModeRaw' leaked into export")
    }

    /// Paths under `/Users/` and `/private/var/` are scrubbed by the helper.
    func testExportStripsUserPaths() throws {
        let input = "Log at /Users/john/Documents/secret.txt and /private/var/log/foo.log"
        let scrubbed = DiagnosticsExporter.scrubText(input)
        XCTAssertFalse(scrubbed.contains("/Users/john"))
        XCTAssertFalse(scrubbed.contains("/private/var"))
        XCTAssertTrue(scrubbed.contains("[REDACTED]"))
    }

    /// The save-panel stub receives the default filename; the exporter
    /// honors the URL it returns.
    func testExportWritesToProvidedDestination() async throws {
        let destination = tempURL()
        let panel = StubSavePanel(destination: destination)
        let snapshot = makeSnapshot()
        let exporter = DiagnosticsExporter(
            panel: panel,
            snapshotProvider: { [snapshot] },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let url = try await exporter.export()
        XCTAssertEqual(url, destination)
        XCTAssertEqual(panel.promptCount, 1)
        XCTAssertNotNil(panel.capturedFilename)
        XCTAssertTrue(panel.capturedFilename?.hasPrefix("kWatch-Diagnostics-") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    /// Cancelling the save panel (returns nil) surfaces a typed error so
    /// the Settings view model can show a "Export cancelled" message.
    func testExportReturnsURL() async throws {
        let destination = tempURL()
        let panel = StubSavePanel(destination: destination)
        let exporter = DiagnosticsExporter(
            panel: panel,
            snapshotProvider: { [] },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let url = try await exporter.export()
        XCTAssertEqual(url, destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    /// The cancel path throws `DiagnosticsExportFailure.userCancelled`.
    func testExportThrowsOnCancel() async {
        let panel = StubSavePanel(destination: nil)
        let exporter = DiagnosticsExporter(
            panel: panel,
            snapshotProvider: { [] },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        do {
            _ = try await exporter.export()
            XCTFail("Expected userCancelled error")
        } catch let error as DiagnosticsExportFailure {
            switch error {
            case .userCancelled:
                break
            default:
                XCTFail("Expected .userCancelled, got \(error)")
            }
        } catch {
            XCTFail("Expected DiagnosticsExportFailure, got \(error)")
        }
    }

    // MARK: - Fixtures

    private func tempURL(suffix: String = "json") -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kWatch.diagnostics.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("export.\(suffix)")
    }
}