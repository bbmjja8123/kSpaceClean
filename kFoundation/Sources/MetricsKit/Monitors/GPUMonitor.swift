import Foundation

public final class GPUMonitor: MetricMonitor, @unchecked Sendable {
    public let kind: MetricKind = .gpu

    private let smcProvider: any SMCReadingProvider
    private let usageProvider: any GPUUsageProvider

    /// Designated init. `usageProvider` defaults to `MetalGPUUsageProvider`
    /// on macOS (Apple Silicon only — Intel reports `.unsupported`).
    /// Tests inject `StubGPUUsageProvider` so the contract is verifiable
    /// without a real Metal device.
    public init(
        smcProvider: any SMCReadingProvider,
        usageProvider: any GPUUsageProvider = MetalGPUUsageProvider()
    ) {
        self.smcProvider = smcProvider
        self.usageProvider = usageProvider
    }

    public func sample() async throws -> MetricSample {
        // Prefer the usage reading — that's what the dashboard wants to
        // plot. Fall back to SMC temperature if the usage provider says
        // this Mac has no Metal-driven GPU telemetry (e.g. Intel iGPU).
        if usageProvider.isSupported, let fraction = try? usageProvider.sampleUsageFraction() {
            return MetricSample(
                kind: .gpu,
                value: .percentage(fraction),
                availability: .available,
                timestamp: Date()
            )
        }

        // Fallback: surface the SMC temperature if available. Most Intel
        // Macs still expose a `TG0P` SMC key even when Metal can't give us
        // a working-set fraction.
        //
        // Known consumer mismatch (Intel-only, pre-existing, kept
        // intentionally): this branch emits `.degreesCelsius` under the
        // `.gpu` kind, while menu-bar/widget consumers expect `.gpu` to be
        // `.percentage`. Apple Silicon never reaches this branch (Metal
        // telemetry is supported), so the mismatch is cosmetic on Intel only.
        if smcProvider.isSupported, let gpuTemp = try? smcProvider.read(key: .gpuTemperature) {
            return MetricSample(
                kind: .gpu,
                value: .degreesCelsius(gpuTemp),
                availability: .available,
                timestamp: Date()
            )
        }

        return MetricSample(
            kind: .gpu,
            value: .unavailable(.unsupported("GPU telemetry is unavailable on this Mac")),
            availability: .unsupported(reason: "GPU telemetry is unavailable on this Mac"),
            timestamp: Date()
        )
    }
}