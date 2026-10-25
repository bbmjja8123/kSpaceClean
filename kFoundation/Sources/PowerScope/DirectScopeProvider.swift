// kFoundation/Sources/PowerScope/DirectScopeProvider.swift
//
// Scope provider for the direct (Developer ID) channel.
//
// The direct edition ships without App Sandbox, so the whole
// grant-home-folder-via-bookmark dance is meaningless: every path is
// readable once macOS TCC grants Full Disk Access to the app (or the user
// simply runs from a non-TCC location for non-protected paths). This
// provider reports ``ScopeLevel.fullAccess`` unconditionally and makes the
// grant/revoke flow a no-op, so every consumer written against the MAS
// three-level model (``PowerScope``) keeps working unchanged.

import Foundation

/// A ``PowerScopeProviding`` that always reports ``ScopeLevel.fullAccess``.
///
/// Returned by `AppScope`/`AppGraph` when the app was built for the direct
/// channel (`DISTRIBUTION_DIRECT`). Stateless — no bookmark store, no probe.
public struct DirectScopeProvider: PowerScopeProviding {
    public init() {}

    public func capability() async -> ScopeCapability {
        ScopeCapability(level: .fullAccess)
    }

    /// Stateless — nothing to re-resolve; returns the fixed capability.
    public func refresh() async -> ScopeCapability {
        await capability()
    }

    /// No-op in the direct channel — there is nothing to grant. Returns the
    /// current (`.fullAccess`) capability so callers can adopt it uniformly.
    public func grantHomeFolder() async throws -> ScopeCapability {
        await capability()
    }

    /// No-op in the direct channel — access cannot be revoked at runtime.
    public func revoke() async {}

    /// Runs `body` directly — no security scope to activate.
    public func withAccess<T: Sendable>(_ url: URL,
                                        _ body: (URL) async throws -> T) async throws -> T {
        try await body(url)
    }
}
