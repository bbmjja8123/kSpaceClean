// kWise/Features/Cleanup/Views/WarningToast.swift
//
// Task C6 — WarningToast (Running App Detection).
//
// A toast that surfaces running-app conflicts surfaced by Task C3's
// `WarningDetectionService` so the user can choose how to proceed before the
// cleanup engine moves anything to Trash. The toast is the standalone
// alternative to the inline warning footer of the old confirm panel (the
// panel was retired in P2 T9 — cleanups now run through the unified
// rehearsal sheet) — it is presented when the warning comes back from the
// engine *after* the user has already confirmed.
//
// The three actions match the v1.0 design (Q11 decision):
// - **Skip** these items — leave the conflicting paths out of the cleanup.
// - **Force terminate** the running apps — issue `kill -TERM` and proceed.
// - **Cancel** the cleanup run entirely.
//
// This view is intentionally a *pure presentation*: it owns no state, it
// does not call the engine, and it does not know about Core Data. Callers
// drive the dismiss/protocol logic by closing over the supplied callbacks.
import SwiftUI

/// A toast that lists running apps that have files open underneath
/// paths the user is about to clean, and offers three resolution actions.
///
/// The toast is meant to be presented as the upper-most level above whatever
/// confirmation sheet is on screen. It is *not* a navigation view — it owns
/// no state and never calls into the engine. The caller supplies the
/// resolution callbacks (skip / terminate / abort) and dismisses the toast
/// once one of them fires.
///
/// **Visual contract:**
/// - Warning-tinted border + warning icon to distinguish from the regular
///   confirmation sheet.
/// - One row per conflicting app, with the conflicting-path count and the
///   aggregate size of those paths on disk.
/// - Three buttons in a clear left-to-right severity order (Skip → Terminate
///   → Cancel) so the user does not have to read copy to pick safely.
///
/// **Accessibility:**
/// - Each button has a clear label with an explicit accessibility role so
///   VoiceOver can describe the destructive intent.
/// - The aggregate message is combined into a single element so the screen
///   reader does not read three separate "1 of 3" announcements.
struct WarningToast: View {
    /// Apps that have a file open underneath one of the paths the user is
    /// about to clean. Empty arrays are technically supported but the toast
    /// is meaningless in that state — the caller should not present it.
    let warnItems: [WarnItem]
    /// Closure invoked when the user asks to leave the conflicting paths out
    /// of the cleanup. The engine will skip these paths and proceed.
    let onSkip: () -> Void
    /// Closure invoked when the user wants to terminate the running apps so
    /// the cleanup can proceed without conflict. The engine is responsible
    /// for issuing `kill -TERM` against the PIDs listed in ``warnItems``.
    let onTerminate: () -> Void
    /// Closure invoked when the user wants to abort the entire cleanup run.
    let onAbort: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Headline — icon + count + framing copy.
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.stateWarning)
                    .accessibilityHidden(true)

                Text(String(format: String(localized: String.LocalizationValue("检测到 %@ 个运行中应用涉及您选择的清理项")),
                            String(warnItems.count)))
                    .font(Typography.mediumTitle())
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.leading)
                    .accessibilityLabel(headlineAccessibilityLabel)
            }

            Divider().background(Color.divider)

            // Per-app conflict list. We render every entry so the user can
            // see exactly which apps would be terminated or skipped.
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(warnItems) { item in
                    warningRow(for: item)
                }
            }

            Divider().background(Color.divider)

            // Action row — skip / terminate / cancel, in that order.
            HStack(spacing: Spacing.sm) {
                Button(String(localized: String.LocalizationValue("warn.toast.skip")), action: onSkip)
                    .buttonStyle(.bordered)
                    .help(String(localized: String.LocalizationValue("warn.toast.skip.help")))
                    .accessibilityLabel(String(localized: String.LocalizationValue("warn.toast.skip")))
                    .accessibilityHint(String(localized: String.LocalizationValue("warn.toast.skip.hint")))

                Button(String(localized: String.LocalizationValue("warn.toast.terminate")), action: onTerminate)
                    .buttonStyle(.bordered)
                    .tint(.riskDangerous)
                    .help(String(localized: String.LocalizationValue("warn.toast.terminate.help")))
                    .accessibilityLabel(String(localized: String.LocalizationValue("warn.toast.terminate")))
                    .accessibilityHint(String(localized: String.LocalizationValue("warn.toast.terminate.hint")))

                Button(String(localized: String.LocalizationValue("warn.toast.cancel")), role: .cancel, action: onAbort)
                    .buttonStyle(.bordered)
                    .help(String(localized: String.LocalizationValue("warn.toast.cancel.help")))
                    .accessibilityLabel(String(localized: String.LocalizationValue("warn.toast.cancel")))
                    .accessibilityHint(String(localized: String.LocalizationValue("warn.toast.cancel.hint")))
            }
        }
        .padding(Spacing.md)
        .frame(width: 480)
        .background(Color.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(Color.stateWarning, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Sub-views

    /// One row per conflicting app: name + bundle ID + PID, plus the
    /// conflicting-path count and aggregate size on disk.
    ///
    /// The size is computed lazily from the conflicting paths so the view
    /// stays a pure function of its inputs — callers do not need to provide
    /// a pre-built ``WarnItem.totalSize`` field. ``WarnItem`` itself does
    /// not carry a pre-computed size; this is the canonical place to
    /// surface it.
    @ViewBuilder
    private func warningRow(for item: WarnItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: String(localized: String.LocalizationValue("%@ (%@) - PID %@")),
                        item.appName, item.bundleID, String(item.processID)))
                .font(Typography.regularBody())
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(String(format: String(localized: String.LocalizationValue("冲突路径 %@ 个 · 共 %@")),
                        String(item.conflictingPaths.count), formatBytes(aggregateSize(for: item))))
                .font(Typography.smallBody())
                .foregroundStyle(Color.textSecondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            format: String(localized: String.LocalizationValue("warn.toast.row.a11y")),
            item.appName, String(item.processID), String(item.conflictingPaths.count),
            formatBytes(aggregateSize(for: item))))
    }

    // MARK: - Derived state

    /// VoiceOver-friendly version of the headline that reads naturally.
    private var headlineAccessibilityLabel: String {
        String(format: String(localized: String.LocalizationValue("warn.toast.headline.a11y")),
               String(warnItems.count))
    }

    // MARK: - Helpers

    /// Aggregate the on-disk size of every conflicting path under ``item``.
    ///
    /// Paths that have been deleted between detection and presentation
    /// (e.g. the user closed the app, the OS reclaimed the file) are
    /// silently dropped — they contribute `0` to the total. Missing files
    /// would otherwise generate noisy I/O errors in the UI.
    private func aggregateSize(for item: WarnItem) -> Int64 {
        var total: Int64 = 0
        for path in item.conflictingPaths {
            guard let size = sizeOnDisk(for: path) else { continue }
            total += size
        }
        return total
    }

    /// Return the size in bytes of a single filesystem path, or `nil` when
    /// the path is missing or unreadable.
    ///
    /// We use ``FileManager.default`` rather than the lower-level
    /// `URL.resourceValues(forKeys:)` so the result matches what Finder
    /// reports when the user inspects the same file in Get Info.
    private func sizeOnDisk(for path: String) -> Int64? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.int64Value
    }

    /// Localized byte formatter — uses `ByteCountFormatter` so the locale
    /// matches the user's macOS settings.
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#if DEBUG
/// SwiftUI previews for ``WarningToast``. Two cases cover the common
/// matrix: a small single-app conflict and a multi-app conflict that
/// crosses CMM/Xcode-class bundle IDs.
struct WarningToast_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            WarningToast(
                warnItems: [
                    WarnItem(
                        appName: "Sketch",
                        bundleID: "com.bohemiancoding.sketch3",
                        processID: 501,
                        conflictingPaths: ["/Users/me/Library/Caches/Sketch/index.db"]
                    ),
                ],
                onSkip: {},
                onTerminate: {},
                onAbort: {}
            )

            WarningToast(
                warnItems: [
                    WarnItem(
                        appName: "Sketch",
                        bundleID: "com.bohemiancoding.sketch3",
                        processID: 501,
                        conflictingPaths: [
                            "/Users/me/Library/Caches/Sketch/index.db",
                            "/Users/me/Library/Caches/Sketch/preview-cache",
                        ]
                    ),
                    WarnItem(
                        appName: "Xcode",
                        bundleID: "com.apple.dt.Xcode",
                        processID: 998,
                        conflictingPaths: [
                            "/Users/me/Library/Developer/Xcode/DerivedData/ModuleCache",
                        ]
                    ),
                ],
                onSkip: {},
                onTerminate: {},
                onAbort: {}
            )
        }
        .padding(40)
        .background(Color.bgPrimary)
        .preferredColorScheme(.dark)
    }
}
#endif
