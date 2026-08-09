import SwiftUI

/// Confirmation sheet shown after the user taps "卸载" on
/// ``AppDetailView``. Renders the 4-level residue risk classification
/// (🟢 Recommended / ⚪ Optional / 🟠 Caution / 🔴 Dangerous) defined in
/// CLAUDE.md §8.6, with defaults set per spec §2.1: recommended ON, the
/// other three OFF.
///
/// The user can toggle individual residues within each bucket; the
/// confirm callback receives the final selection (an empty array means
/// "uninstall the app body only"). When any 🔴 Dangerous residue is
/// selected, the user must type the literal string "DELETE" to unlock the
/// confirm button — a deliberate friction matching CMM X's uninstall flow.
///
/// All size values render via the local `Int64.kbFormatted` helper that
/// wraps `ByteCountFormatter` — kept file-local so the global formatter
/// never gets a divergent shorthand (e.g. "1 KB" vs "1 kB").
struct UninstallConfirmSheet: View {
    let app: InstalledApp
    let residues: [ResidueFile]
    /// Called with the final user-selected residue subset when the user
    /// confirms. An empty array means "app body only" (all residue boxes
    /// unchecked). A `Bool` is no longer enough now that residues are
    /// individually selectable per risk bucket.
    let onConfirm: ([ResidueFile]) -> Void
    let onCancel: () -> Void

    /// Per-residue selection. Initialized once in `init` from the spec's
    /// default-on / default-off policy so opening the sheet always shows
    /// the recommended preset.
    @State private var selectedIDs: Set<String>
    /// Required typed input when any 🔴 Dangerous residue is selected.
    /// Case-sensitive match against the literal "DELETE".
    @State private var dangerousConfirmation: String = ""

    /// Case-sensitive literal that the user must type to confirm a
    /// uninstall that includes any Dangerous residue. Exposed as a static
    /// constant so tests and the host view can reference the same string.
    static let dangerousConfirmLiteral = "DELETE"

    init(app: InstalledApp,
         residues: [ResidueFile],
         onConfirm: @escaping ([ResidueFile]) -> Void,
         onCancel: @escaping () -> Void) {
        self.app = app
        self.residues = residues
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        // v1.x-D: route the initial selection through ResidueSmartSelector
        // rather than the hard-coded `riskLevel == .recommended` filter.
        // The smart selector adds the Nektony-style "stale optional" rule
        // (180 days since last use → Optional bucket also defaults ON).
        _selectedIDs = State(initialValue: ResidueSmartSelector.defaultSelection(
            residues: residues,
            app: app
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            header
            summary
            residueSections
            footer
        }
        .padding(AppSpacing.lg)
        .frame(width: WindowFrame.confirmSheetWidth)
        .background(Color.bgPrimary)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("卸载 \(app.displayName)?")
                    .font(AppFont.title3)
                if app.isRunning {
                    Label("App 正在运行，将先退出再卸载", systemImage: "exclamationmark.triangle")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.warning)
                }
                if app.source == .mas {
                    Label("此 App 来自 App Store，可随时重新下载", systemImage: "info.circle")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            row("App 本体", value: app.sizeBytes.kbFormatted)
            if !selectedResidues.isEmpty {
                row("残留文件（已选 \(selectedResidues.count) 项）", value: selectedResiduesSize.kbFormatted)
            } else if !residues.isEmpty {
                row("残留文件", value: "未选")
                    .foregroundStyle(Color.textSecondary)
            }
            Divider()
            HStack {
                Text("共释放").font(AppFont.title3)
                Spacer()
                Text(totalFreedSize.kbFormatted)
                    .font(AppFont.title3)
            }
            Label("移入废纸篓（可回滚 30 天）", systemImage: "arrow.uturn.backward")
                .font(AppFont.caption)
                .foregroundStyle(Color.success)
        }
        .padding(AppSpacing.md)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var residueSections: some View {
        if !residues.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ForEach(ResidueRiskLevel.allCases, id: \.self) { level in
                    let bucket = residues.filter { $0.riskLevel == level }
                    if !bucket.isEmpty {
                        ResidueRiskSection(
                            level: level,
                            residues: bucket,
                            selectedIDs: $selectedIDs
                        )
                    }
                }
                if selectedResidues.contains(where: { $0.riskLevel == .dangerous }) {
                    dangerousGate
                }
            }
        }
    }

    private var dangerousGate: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Label("高危操作确认", systemImage: "exclamationmark.octagon")
                .font(AppFont.callout)
                .foregroundStyle(Color.danger)
            Text("已选择的高危项会立即生效。请输入 \(Self.dangerousConfirmLiteral) 以继续。")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
            TextField(Self.dangerousConfirmLiteral, text: $dangerousConfirmation)
                .textFieldStyle(.roundedBorder)
                .font(AppFont.monoDigit)
        }
        .padding(AppSpacing.md)
        .background(Color.danger.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack {
            Button("取消", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)
            Spacer()
            Button("确认卸载", role: .destructive) {
                onConfirm(selectedResidues)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.danger)
            .disabled(!canConfirm)
        }
    }

    // MARK: - Derived state

    /// The subset of ``residues`` the user has currently selected.
    private var selectedResidues: [ResidueFile] {
        residues.filter { selectedIDs.contains($0.id) }
    }

    /// Sum of `sizeBytes` across all currently selected residues.
    private var selectedResiduesSize: Int64 {
        selectedResidues.reduce(0) { $0 + $1.sizeBytes }
    }

    /// App body + selected residues (zero residue contribution when none
    /// are selected, matching the legacy `includeResidues: false` path).
    private var totalFreedSize: Int64 {
        app.sizeBytes + selectedResiduesSize
    }

    /// Whether the confirm button should be enabled. Disabled when a
    /// 🔴 Dangerous residue is selected but the user has not typed the
    /// required literal.
    private var canConfirm: Bool {
        let hasDangerous = selectedResidues.contains { $0.riskLevel == .dangerous }
        return !hasDangerous || dangerousConfirmation == Self.dangerousConfirmLiteral
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(AppFont.body)
            Spacer()
            Text(value).font(AppFont.monoDigit)
        }
    }
}

// MARK: - Per-risk section

/// One collapsible bucket inside ``UninstallConfirmSheet`` for a single
/// ``ResidueRiskLevel``. Renders a section header with a bulk toggle and
/// a row of per-residue checkboxes.
private struct ResidueRiskSection: View {
    let level: ResidueRiskLevel
    let residues: [ResidueFile]
    @Binding var selectedIDs: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(level.sectionTitle)
                    .font(AppFont.callout)
                Text("（\(residues.count) 项 · \(bucketSize.kbFormatted)）")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Toggle("", isOn: bucketToggleBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .help(bucketToggleHelp)
            }
            ForEach(residues, id: \.id) { residue in
                Toggle(isOn: bindingFor(residue)) {
                    HStack {
                        Text(residue.description.isEmpty ? residue.type.displayName : residue.description)
                            .font(AppFont.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(residue.sizeBytes.kbFormatted)
                            .font(AppFont.monoDigit)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(AppSpacing.md)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var bucketSize: Int64 {
        residues.reduce(0) { $0 + $1.sizeBytes }
    }

    private func bindingFor(_ residue: ResidueFile) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(residue.id) },
            set: { isOn in
                if isOn { selectedIDs.insert(residue.id) }
                else { selectedIDs.remove(residue.id) }
            }
        )
    }

    private var bucketToggleBinding: Binding<Bool> {
        Binding(
            get: { bucketSelectedCount == residues.count },
            set: { isOn in
                if isOn {
                    for r in residues { selectedIDs.insert(r.id) }
                } else {
                    for r in residues { selectedIDs.remove(r.id) }
                }
            }
        )
    }

    private var bucketSelectedCount: Int {
        residues.filter { selectedIDs.contains($0.id) }.count
    }

    private var bucketToggleHelp: String {
        bucketSelectedCount == residues.count ? "取消全选" : "全选"
    }
}

// MARK: - Local formatting helper

/// File-local `Int64` byte formatter wrapper. Intentionally kept private to
/// `UninstallConfirmSheet.swift` so the design system's overall byte-display
/// policy stays controlled — adding a global extension would let other
/// modules diverge from this style without a code-review signal.
private extension Int64 {
    var kbFormatted: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

// MARK: - ResidueType display name (file-local)

private extension ResidueType {
    /// Short, Chinese-localized label used inside the per-residue toggle
    /// rows so the user can identify a residue without seeing its raw
    /// path. Mirrors the description strings in
    /// `ResidueDetector.descriptionForType(_:)` but kept local so the
    /// confirm sheet can shorten or reword without touching the detector.
    var displayName: String {
        switch self {
        case .preferences:    return "偏好设置"
        case .caches:         return "缓存文件"
        case .appSupport:     return "应用支持文件"
        case .log:            return "日志文件"
        case .savedState:     return "保存的应用状态"
        case .container:      return "Sandbox 容器"
        case .cookie:         return "Cookies"
        case .webKit:         return "WebKit 缓存"
        case .httpStorage:    return "HTTP 存储"
        case .groupContainer: return "Group 容器"
        case .appleScript:    return "AppleScript 自动化"
        case .plugin:         return "插件"
        case .launchAgent:    return "启动代理"
        case .launchDaemon:   return "启动守护"
        case .prefPane:       return "偏好设置面板"
        case .startupItem:    return "启动项"
        case .other:          return "其他"
        }
    }
}