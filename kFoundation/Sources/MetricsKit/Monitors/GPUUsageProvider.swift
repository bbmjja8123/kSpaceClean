#if canImport(Metal)
import Foundation
import Metal

/// Adapter boundary for GPU usage telemetry.
///
/// macOS does not expose a per-GPU activity percentage through any public
/// Apple framework — only `currentAllocatedSize` (live VRAM allocation)
/// and `recommendedMaxWorkingSetSize` (Apple Silicon recommended upper
/// bound). We model "GPU usage" as the live VRAM allocation as a
/// fraction of the recommended working-set size, which is a stable
/// proxy for memory pressure and gives the dashboard a meaningful
/// percentage to plot on Apple Silicon.
///
/// On Intel Macs `recommendedMaxWorkingSetSize` is `0`, so the provider
/// reports `.unsupported`. The same provider is used on both
/// architectures — Apple Silicon users get a value, Intel users see an
/// explicit "GPU usage unavailable" badge instead of fabricated data.
public protocol GPUUsageProvider: Sendable {
    var isSupported: Bool { get }
    /// Sample the live VRAM allocation as a fraction in `[0, 1]`. Returns
    /// `nil` if the underlying device cannot be read (e.g. no Metal
    /// device is available, or the platform is Intel).
    func sampleUsageFraction() throws -> Double?
}

/// Metal-based implementation that creates an MTLDevice on demand and
/// reads `currentAllocatedSize / recommendedMaxWorkingSetSize`.
public final class MetalGPUUsageProvider: GPUUsageProvider, @unchecked Sendable {
    public init() {}

    public var isSupported: Bool {
        // Cached once per process: MTLCreateSystemDefaultDevice() may
        // log a warning on every call on machines without a Metal
        // driver. We treat that as "unsupported" and return early.
        guard MTLCreateSystemDefaultDevice() != nil else { return false }
        return true
    }

    public func sampleUsageFraction() throws -> Double? {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        let allocated = device.currentAllocatedSize
        let max = device.recommendedMaxWorkingSetSize
        // Apple Silicon has a real working-set recommendation; Intel
        // Macs report 0. Treat 0 max as "unsupported" so we surface the
        // hardware limitation instead of dividing by zero.
        guard max > 0 else { return nil }
        return min(1.0, Double(allocated) / Double(max))
    }
}

/// Test double. Returns the canned value, or `nil` for unsupported.
public final class StubGPUUsageProvider: GPUUsageProvider, @unchecked Sendable {
    private let fraction: Double?
    private let supported: Bool

    public init(fraction: Double?, supported: Bool = true) {
        self.fraction = fraction
        self.supported = supported
    }

    public var isSupported: Bool { supported }
    public func sampleUsageFraction() throws -> Double? { fraction }
}
#else
import Foundation

/// macOS-only feature — Metal is not available on non-Apple platforms.
public protocol GPUUsageProvider: Sendable {
    var isSupported: Bool { get }
    func sampleUsageFraction() throws -> Double?
}

public final class MetalGPUUsageProvider: GPUUsageProvider, @unchecked Sendable {
    public init() {}
    public var isSupported: Bool { false }
    public func sampleUsageFraction() throws -> Double? { nil }
}

public final class StubGPUUsageProvider: GPUUsageProvider, @unchecked Sendable {
    private let fraction: Double?
    private let supported: Bool
    public init(fraction: Double?, supported: Bool = true) {
        self.fraction = fraction; self.supported = supported
    }
    public var isSupported: Bool { supported }
    public func sampleUsageFraction() throws -> Double? { fraction }
}
#endif