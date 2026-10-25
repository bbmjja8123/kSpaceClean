// kWise/Features/Common/DistributionChannel.swift
//
// The single seam where the two distribution channels diverge.
//
// Klaris ships in two editions from one source tree (P3 dual-channel):
// * ``macAppStore`` — sandboxed (`kWise` target, `DISTRIBUTION_MAS`); scans
//   run through PowerScope's grant-home-folder flow.
// * ``direct`` — non-sandboxed Developer ID build (`KlarisDirect` target,
//   `DISTRIBUTION_DIRECT`); scans assume the real home directory is readable
//   and the grant flow is a no-op (`DirectScopeProvider`).
//
// Every channel-specific behavior (grant UI, FDA row, paywall guidance,
// scan messaging) must read ``DistributionChannel.current`` from here —
// this file is the ONLY place allowed to branch on the
// `DISTRIBUTION_MAS` / `DISTRIBUTION_DIRECT` compile conditions, so the
// channel matrix stays auditable in one screen.

import Foundation

/// Which distribution channel this build was produced for.
public enum DistributionChannel: Sendable, Equatable {
    case macAppStore
    case direct

    /// The channel this binary was compiled for. When neither compile
    /// condition is set (ad-hoc builds, previews), fall back to a runtime
    /// sandbox probe: in a sandboxed process `NSHomeDirectory()` returns the
    /// container while libc's passwd entry still points at the real home.
    public static let current: DistributionChannel = {
        #if DISTRIBUTION_DIRECT
        return .direct
        #elseif DISTRIBUTION_MAS
        return .macAppStore
        #else
        return isRuntimeSandboxed() ? .macAppStore : .direct
        #endif
    }()

    /// `true` when the process runs inside the App Sandbox.
    ///
    /// Derived from ``current`` rather than probed per call: the channel
    /// flags and the runtime probe agree in every shipping configuration,
    /// and tests can drive behavior deterministically through ``current``.
    public static var isSandboxed: Bool { current == .macAppStore }

    /// Runtime sandbox probe used only when no channel flag was compiled in.
    private static func isRuntimeSandboxed() -> Bool {
        UserPathResolver.realHomeDirectory() != NSHomeDirectory()
    }
}
