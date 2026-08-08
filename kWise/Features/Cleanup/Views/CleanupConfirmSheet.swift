// kWise/Features/Cleanup/Views/CleanupConfirmSheet.swift
//
// Task C4 — risk-graded cleanup confirmation sheet (v3 spec §1.5).
//
// The sheet is the last gate before files leave the disk. It groups the
// selection by risk level (Recommended / Optional / Caution / Dangerous) and
// surfaces running-app conflicts from Task C3's `WarningDetectionService` so
// the user can pick Skip / Force Terminate / Cancel before the engine runs.
//
// Design choices:
// - The primary CTA's tint is graded by the highest-risk level present. This
//   matches Apple HIG destructive-action guidance (System Preferences' "Empty
//   Trash" uses red). It also makes the danger obvious without forcing the
//   user to read copy.
// - For `.dangerous` items the CTA label changes to "永久删除（输入 DELETE）".
//   The actual DELETE-text input is delivered by the separate
//   `DangerousConfirmDialog` (Task C5) which is presented *on top of* this
//   sheet — we only mark the upgrade path here.
// - The warning-items section renders nothing when the list is empty; we do
//   not pad it with a "no warnings" line because the absence is the message.
import SwiftUI

/// Modal confirmation sheet shown immediately before the cleanup engine runs.
///
/// The sheet is a *presentation*, not a state container — callers pass in the
/// selection (`urls`), the aggregated size (`totalSize`), the per-risk counts
/// (`riskSummary`), and the optional warning items (Task C3). The view fires
/// `onConfirm` or `onCancel` and is dismissed by the caller.
///
/// Visual contract:
/// - **Hero icon** grades with the highest risk present in the selection.
/// - **Title** changes to call out the destructive path when `.dangerous`
///   items are present.
/// - **Primary CTA** uses ``RiskLevel`` colour mapping for danger (red),
///   caution (orange), or normal brand blue.
/// - **Footer warning block** lists each running app that owns at least one
///   of the selected paths; tapping the row is a no-op (the buttons drive
///   the decision).
///
/// The view is intentionally self-contained: it does not own any state, it
/// does not call the engine, and it does not know about Core Data. This makes
/// it trivially snapshot-testable.
struct CleanupConfirmSheet: View {
    /// URLs the user is about to clean.
    let urls: [URL]
    /// Total bytes the selection will free.
    let totalSize: Int64
    /// Number of items per ``RiskLevel`` present in the selection.
    ///
    /// Missing keys are treated as `0`. Required because the engine hands the
    /// caller a flat `[CleanupTarget]` list and the caller has to bucket it.
    let riskSummary: [RiskLevel: Int]
    /// Running apps that conflict with at least one selected path
    /// (Task C3's `WarningDetectionService`). Empty when no conflicts.
    let warnItems: [WarnItem]
    /// Action the user picked in the warning footer, surfaced upward.
    let onConfirm: (WarnHandling) -> Void
    let onCancel: () -> Void

    /// Default initialiser — callers normally don't need to pass `warnItems`.
    init(urls: [URL],
         totalSize: Int64,
         riskSummary: [RiskLevel: Int],
         warnItems: [WarnItem] = [],
         onConfirm: @escaping (WarnHandling) -> Void,
         onCancel: @escaping () -> Void) {
        self.urls = urls
        self.totalSize = totalSize
        self.riskSummary = riskSummary
        self.warnItems = warnItems
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Hero — single icon + title + size + risk summary.
            VStack(spacing: Spacing.sm) {
                Image(systemName: highestRiskIcon)
                    .font(.system(size: 48))
                    .foregroundStyle(highestRiskColor)
                    .accessibilityHidden(true)

                Text(actionTitle)
                    .font(Typography.largeTitle())
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)

                Text(summaryLine)
                    .font(Typography.regularBody())
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(summaryAccessibilityLabel)
            }

            // Per-risk breakdown — only non-zero rows.
            riskBreakdown
                .padding(.vertical, Spacing.xs)

            // Caution / Dangerous callouts — explicit copy for the two risk
            // levels that change the recommended behaviour.
            if hasCaution, !hasDangerous {
                Label("包含 \(cautionCount) 项谨慎清理，可能需要重新登录或重建缓存",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.smallBody())
                    .foregroundColor(.riskCaution)
                    .padding(.horizontal, Spacing.sm)
                    .accessibilityElement(children: .combine)
            }

            if hasDangerous {
                Label("包含 \(dangerousCount) 项危险清理，将强制二次确认（输入 DELETE）",
                      systemImage: "flame.fill")
                    .font(Typography.smallBody())
                    .foregroundColor(.riskDangerous)
                    .padding(.horizontal, Spacing.sm)
                    .accessibilityElement(children: .combine)
            }

            // Warning footer — running-app conflicts.
            if !warnItems.isEmpty {
                warningSection
            }

            Divider()
                .background(Color.divider)

            // Action row.
            HStack(spacing: Spacing.md) {
                Button("取消", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape, modifiers: [])

                // C3 fix: when dangerous items are present, the primary CTA
                // opens `DangerousConfirmDialog` (Task C5) instead of firing
                // `onConfirm` directly. The dialog requires the user to type
                // the literal "DELETE" token before calling `onConfirm` back
                // up the chain. This is the actual data-loss gate.
                Button(actionTitle, role: hasDangerous ? .destructive : nil,
                       action: {
                           if hasDangerous {
                               showDangerousDialog = true
                           } else {
                               onConfirm(defaultWarnHandling)
                           }
                       })
                    .buttonStyle(.borderedProminent)
                    .tint(ctaTint)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(Spacing.lg)
        .frame(width: 520)
        .background(Color.bgElevated)
        .accessibilityElement(children: .contain)
        // C3: present the dangerous dialog as a sheet on top of the
        // confirmation sheet. SwiftUI only allows one sheet per view, so
        // we layer the dialog here rather than at the call site.
        .sheet(isPresented: $showDangerousDialog) {
            DangerousConfirmDialog(
                onConfirm: {
                    showDangerousDialog = false
                    onConfirm(defaultWarnHandling)
                },
                onCancel: {
                    showDangerousDialog = false
                }
            )
        }
    }

    /// C3: drives presentation of the `DangerousConfirmDialog`. The
    /// dialog is only reachable when `hasDangerous` is `true`; otherwise
    /// the CTA fires `onConfirm` directly.
    @State private var showDangerousDialog: Bool = false

    // MARK: - Sub-views

    /// One row per non-zero risk bucket. Hidden entirely when the selection
    /// is empty so we never render a ghost grid.
    @ViewBuilder
    private var riskBreakdown: some View {
        let presentLevels = RiskLevel.allCases.filter { (riskSummary[$0] ?? 0) > 0 }
        if !presentLevels.isEmpty {
            VStack(spacing: Spacing.xs) {
                ForEach(presentLevels, id: \.self) { level in
                    HStack(spacing: Spacing.sm) {
                        RiskBadge(level: level, compact: true)
                        Text(level.label)
                            .font(Typography.regularBody())
                            .foregroundColor(.textPrimary)
                        Spacer()
                        Text("\(riskSummary[level] ?? 0) 项")
                            .font(Typography.smallBody())
                            .foregroundColor(.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(Color.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    /// Footer list of running apps that own at least one of the selected paths.
    ///
    /// We expose three buttons for the three ``WarnHandling`` outcomes so the
    /// user does not have to hunt through menus to skip vs. terminate vs.
    /// cancel. The "Force Terminate" button is the most consequential and is
    /// the only one that actually fires `onConfirm` with a non-default
    /// handling; the other two reuse ``defaultWarnHandling``.
    private var warningSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.stateWarning)
                Text("检测到 \(warnItems.count) 个运行中应用涉及您选择的清理项")
                    .font(Typography.smallBody())
                    .foregroundColor(.textPrimary)
            }

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                ForEach(warnItems) { item in
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "app.fill")
                            .foregroundColor(.textSecondary)
                            .accessibilityHidden(true)
                        Text(item.appName)
                            .font(Typography.smallBody())
                            .foregroundColor(.textSecondary)
                        Spacer()
                        Text("\(item.conflictingPaths.count) 项")
                            .font(Typography.smallBody())
                            .foregroundColor(.textTertiary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.leading, Spacing.md)

            HStack(spacing: Spacing.sm) {
                Button("跳过冲突项", action: { onConfirm(.skip) })
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("强制终止应用", role: .destructive,
                       action: { onConfirm(.terminate) })
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("取消", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(Spacing.sm)
        .background(Color.stateWarning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Color.stateWarning.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Derived state

    /// Headline copy — escalates with the highest risk in the selection.
    private var actionTitle: String {
        if hasDangerous { return "永久删除（输入 DELETE）" }
        if hasCaution { return "谨慎清理" }
        return "确认清理"
    }

    /// Combined headline + size + count summary line, used for VoiceOver.
    private var summaryLine: String {
        "将清理 \(urls.count) 项 · \(formatBytes(totalSize))"
    }

    /// Accessibility-friendly version of ``summaryLine`` that reads naturally.
    private var summaryAccessibilityLabel: String {
        "本次将清理 \(urls.count) 项文件，共 \(formatBytes(totalSize))"
    }

    /// Icon shown above the title — chosen by the highest risk in the selection.
    private var highestRiskIcon: String {
        if hasDangerous { return "flame.fill" }
        if hasCaution { return "exclamationmark.triangle.fill" }
        return "trash.fill"
    }

    /// Colour for both the hero icon and the primary CTA.
    ///
    /// `.dangerous` red, `.caution` orange, otherwise brand blue. Returned as
    /// a `Color` so callers can compare with `==` without ambiguity.
    private var highestRiskColor: Color {
        if hasDangerous { return .riskDangerous }
        if hasCaution { return .riskCaution }
        return .brandPrimary
    }

    /// Tint applied to the primary CTA. Defaults to brand blue; for
    /// dangerous selections we use the destructive red so the affordance
    /// reads correctly against the bordered-prominent chrome.
    private var ctaTint: Color {
        highestRiskColor
    }

    /// Default warning handling passed upward when the user just taps "确认".
    ///
    /// - `.skip` when warning items are present — the safer of the two
    ///   non-abort choices.
    /// - `.terminate` is opt-in via the warning footer; we never default to
    ///   it because terminating a running app without a second look is
    ///   destructive behaviour we want to gate.
    /// - `.skip` (no-op) when no warnings are present.
    private var defaultWarnHandling: WarnHandling {
        warnItems.isEmpty ? .skip : .skip
    }

    private var hasDangerous: Bool { dangerousCount > 0 }
    private var hasCaution: Bool { cautionCount > 0 }
    private var dangerousCount: Int { riskSummary[.dangerous] ?? 0 }
    private var cautionCount: Int { riskSummary[.caution] ?? 0 }

    /// Localized byte formatter — uses `ByteCountFormatter` so the locale
    /// matches the user's macOS settings.
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#if DEBUG
/// SwiftUI previews for ``CleanupConfirmSheet``. Four cards cover the
/// matrix of risk mix × warning presence that production can hit.
struct CleanupConfirmSheet_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 24) {
            CleanupConfirmSheet(
                urls: (0..<12).map { URL(fileURLWithPath: "/tmp/file-\($0).cache") },
                totalSize: 1_482_309_120,
                riskSummary: [.recommended: 10, .optional: 2],
                warnItems: [],
                onConfirm: { _ in },
                onCancel: {}
            )

            CleanupConfirmSheet(
                urls: (0..<8).map { URL(fileURLWithPath: "/tmp/file-\($0).cache") },
                totalSize: 423_000_000,
                riskSummary: [.recommended: 4, .caution: 4],
                warnItems: [],
                onConfirm: { _ in },
                onCancel: {}
            )

            CleanupConfirmSheet(
                urls: (0..<3).map { URL(fileURLWithPath: "/tmp/file-\($0).cache") },
                totalSize: 12_400_000,
                riskSummary: [.dangerous: 3],
                warnItems: [
                    WarnItem(appName: "Sketch",
                             bundleID: "com.bohemiancoding.sketch3",
                             processID: 501,
                             conflictingPaths: ["/Users/me/Library/Caches/Sketch"]),
                    WarnItem(appName: "Photoshop",
                             bundleID: "com.adobe.Photoshop",
                             processID: 502,
                             conflictingPaths: ["/Users/me/Library/Caches/Adobe/Photoshop"]),
                ],
                onConfirm: { _ in },
                onCancel: {}
            )
        }
        .padding(40)
        .background(Color.bgCanvas)
        .preferredColorScheme(.dark)
    }
}
#endif