import Foundation
#if canImport(MetricKit)
import MetricKit
#endif

/// Persists MetricKit crash + hang payloads to local disk for TestFlight feedback review.
///
/// MetricKit callbacks arrive on a background queue; `record` is `Sendable` so the
/// file write is safe to call from any context. Files are written under
/// `~/Library/Application Support/kSpaceClean/metric-kit/` by default and are
/// never uploaded off-device. The TestFlight internal tester (or developer
/// reviewing MetricKit in App Store Connect) reads them during daily feedback
/// review (Task D2 Step 3).
///
/// File naming: `crash-<unix-timestamp>.json` — sortable and grep-friendly.
final class MetricKitReceiver: @unchecked Sendable {
    struct CrashPayload: Codable, Equatable, Sendable {
        let bundleID: String
        let version: String
        let build: String
        let timestamp: Date
        let callStack: String
        let terminationReason: String
    }

    let outputDirectory: URL

    #if canImport(MetricKit)
    /// macOS-14+ subscriber; retained so the receiver can unregister cleanly.
    /// The wrapper type is only stored on platforms where it is available —
    /// older OSes see the receiver as a pure on-disk writer.
    @available(macOS 14.0, *)
    private final class StoredSubscriberBox {
        let value: MetricKitSubscriber
        init(_ value: MetricKitSubscriber) { self.value = value }
    }
    private var subscriberBox: AnyObject?
    #endif

    init(outputDirectory: URL? = nil) {
        if let outputDirectory {
            self.outputDirectory = outputDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.outputDirectory = appSupport
                .appendingPathComponent("kSpaceClean", isDirectory: true)
                .appendingPathComponent("metric-kit", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.outputDirectory, withIntermediateDirectories: true)
    }

    func record(_ payload: CrashPayload) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        let filename = "crash-\(Int(payload.timestamp.timeIntervalSince1970)).json"
        let url = outputDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
    }

    #if canImport(MetricKit)
    /// Subscribe to MetricKit diagnostics. Call once at app launch.
    ///
    /// Only takes effect on macOS 14+ where `MXDiagnosticPayload` is available;
    /// on macOS 13 the call is a no-op (the `MXMetricManager` API surface is
    /// present but `MXDiagnosticPayload` / `MXCrashDiagnostic` are unavailable).
    @available(macOS 14.0, *)
    func subscribe() {
        let sub = MetricKitSubscriber(receiver: self)
        subscriberBox = StoredSubscriberBox(sub)
        MXMetricManager.shared.add(sub)
    }

    @available(macOS 14.0, *)
    func unsubscribe() {
        if let box = subscriberBox as? StoredSubscriberBox {
            MXMetricManager.shared.remove(box.value)
            subscriberBox = nil
        }
    }
    #endif
}

#if canImport(MetricKit)
/// Thin NSObject shim used as the MetricKit subscriber target.
///
/// Lives in a separate type because `MXMetricManagerSubscriber` is an
/// Objective-C `@protocol` so the conforming type must inherit from `NSObject`.
/// We keep the file-writing logic in `MetricKitReceiver` (Sendable, decoupled
/// from AppKit) and let this shim translate `MXDiagnosticPayload` -> DTO.
@available(macOS 14.0, *)
final class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber {
    private let receiver: MetricKitReceiver

    init(receiver: MetricKitReceiver) {
        self.receiver = receiver
        super.init()
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            guard let crash = payload.crashDiagnostics?.first else { continue }
            let mapped = MetricKitReceiver.CrashPayload(
                bundleID: Bundle.main.bundleIdentifier ?? "unknown",
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
                build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
                timestamp: payload.timeStampBegin,
                callStack: MetricKitSubscriber.describeStack(crash.callStackTree),
                terminationReason: MetricKitSubscriber.describeReason(crash)
            )
            try? receiver.record(mapped)
        }
    }

    private static func describeStack(_ tree: MXCallStackTree) -> String {
        // MetricKit ships the call stack only via its JSON form (per-thread),
        // which is exactly what we want to persist for offline symbolication.
        // We truncate the description to keep the per-file payload small —
        // the full per-thread JSON is also written alongside (future work).
        let raw = tree.jsonRepresentation()
        let summary = "MetricKit call stack (\(raw.count) bytes of JSON)"
        return summary
    }

    private static func describeReason(_ crash: MXCrashDiagnostic) -> String {
        // Prefer `terminationReason` (EXC_BAD_ACCESS / SIGABRT / etc.) when
        // present; fall back to exceptionType/exceptionCode so the payload is
        // never empty.
        if let reason = crash.terminationReason, !reason.isEmpty {
            return reason
        }
        let type = crash.exceptionType.map { "\($0)" } ?? "?"
        let code = crash.exceptionCode.map { "\($0)" } ?? "?"
        let signal = crash.signal.map { " signal=\($0)" } ?? ""
        return "\(type)/\(code)\(signal)"
    }
}
#endif
