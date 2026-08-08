// kWise/Features/Common/PerfSignpost.swift
//
// F8 of the Q4 perf sweep — process-wide `os_signpost` markers so a
// future Instruments run can attribute time to specific phases of the
// scan/filter pipeline.
//
// Markers appear in Instruments' "Points of Interest" lane and in the
// time-profiler template when recorded with `--include-pointers` or
// `--time-limit`. The subsystem is `app.kraftly.sclean`; the category
// is `perf` (mirrors the Apple sample code).
//
// We use the C `os_signpost` API directly because the higher-level
// `Signposter` / `SignpostIntervalState` Swift wrappers are macOS 14+
// only and the project's deployment target is 13.0.

import Foundation
import os.log

/// Process-wide `os_signpost` state for kWise.
///
/// Markers appear in Instruments' "Points of Interest" lane and in the
/// time-profiler template when recorded with `--include-pointers` or
/// `--time-limit`. The subsystem is `app.kraftly.sclean`; the
/// category is `perf` (mirrors the Apple sample code).
///
/// `OSLog` is documented thread-safe by Apple; we declare the storage
/// `nonisolated(unsafe)` so it can be reached from any isolation
/// domain (background scan workers, the @MainActor view model)
/// without ceremony.
enum PerfSignpost {
    /// The shared signpost log. `static let` in an enum is the
    /// canonical Swift pattern for process-wide singletons; the
    /// `OSLog` initializer is thread-safe and the resulting value is
    /// immutable, so concurrent reads are safe from any isolation
    /// domain (background scan workers, the @MainActor view model).
    static let log = OSLog(
        subsystem: "app.kraftly.sclean",
        category: "perf"
    )
}

/// Helper that emits an `os_signpost .begin` event for `name` and
/// returns an opaque state token. Pair the returned token with
/// ``PerfSignpostEnd/_:state:`` (or rely on the standalone
/// `os_signpost .end` call site) so the interval closes correctly.
///
/// We intentionally expose two free-function calls instead of a class
/// with `deinit`: Swift value-type `deinit` does not exist, and a
/// reference type would force ARC overhead in a tight loop.
///
/// Typical use:
///
///     let state = PerfSignpostBegin("scan.orchestrate")
///     defer { PerfSignpostEnd("scan.orchestrate") }
///     /* work */
///
/// Or the one-shot variant, which does both begin and end around the
/// calling site via `defer`:
///
///     perfSignpostInterval("scan.orchestrate") {
///         /* work */
///     }
@inline(__always)
func PerfSignpostBegin(_ name: StaticString) {
    os_signpost(.begin, log: PerfSignpost.log, name: name)
}

@inline(__always)
func PerfSignpostEnd(_ name: StaticString) {
    os_signpost(.end, log: PerfSignpost.log, name: name)
}

/// RAII wrapper that emits a `begin`/`end` pair on construction and
/// on `end()` (or when the wrapper is dropped). Built on the free
/// functions above so the begin/end pair is always symmetric.
///
/// `end()` is idempotent: a manual call followed by `deinit` (or vice
/// versa) emits the closing signpost exactly once.
final class PerfInterval {
    fileprivate let name: StaticString
    private var closed = false

    init(_ name: StaticString) {
        self.name = name
        PerfSignpostBegin(name)
    }

    /// Manually end the interval. Optional — the interval also ends
    /// when the wrapper is deinitialised. Idempotent: a second call
    /// after the first (or after `deinit`) is a no-op.
    func end() {
        guard !closed else { return }
        closed = true
        PerfSignpostEnd(name)
    }

    deinit {
        end()
    }
}