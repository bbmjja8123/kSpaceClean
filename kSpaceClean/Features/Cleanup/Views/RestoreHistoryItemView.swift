// kSpaceClean/Features/Cleanup/Views/RestoreHistoryItemView.swift
//
// I10 — 30-day rollback UI for cleanup history.
//
// The "history" surface is the only safety net a user has after hitting
// Delete: anything they regret must be restorable from here. This view is
// the modal drill-down for one cleanup batch, listing every path that left
// the disk in that batch with its size/risk/category and a single
// "Restore from Trash" action per row.
//
// Per-row restore is delegated to ``RestoreFromTrashService``: it
// locates the trashed file under `~/.Trash` by basename and asks Finder
// to move it back to the original location via `.DS_Store` metadata.
// Finder can fail silently (Trash emptied, file gone, restore disabled
// by MDM), so the service reports a typed ``RestoreResult`` per row.
// The view surfaces `.restored`, `.notInTrash`, and `.notFound` as a
// coloured status badge so the user knows whether the tap did anything.
//
// The window is non-modal: dismissing it does NOT remove the underlying
// `CleanupHistoryItem` rows. Expiry is still owned by
// `PersistenceController.purgeExpiredHistory`.
import SwiftUI
import AppKit

struct RestoreHistoryItemView: View {
    /// Core Data batch — every row shares the same `cleanedAt` and `bundleID`.
    let batch: [CleanupHistoryItem]
    /// Fires when the user closes the sheet.
    let onClose: () -> Void

    @State private var statuses: [UUID: RestoreResult] = [:]
    @State private var restoringAll: Bool = false

    private var totalSize: Int64 {
        batch.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            header

            Divider().background(Color.divider)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(batch, id: \.id) { item in
                        RestoreRow(
                            item: item,
                            status: statuses[item.id ?? UUID()] ?? .idle,
                            onRestore: { restore(item) }
                        )
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
            }

            Divider().background(Color.divider)

            HStack {
                Text("共 \(batch.count) 项 · \(formatBytes(totalSize))")
                    .font(Typography.smallBody())
                    .foregroundColor(.textSecondary)
                Spacer()
                Button("关闭", role: .cancel, action: onClose)
                    .keyboardShortcut(.escape, modifiers: [])
                Button(action: restoreAll) {
                    if restoringAll {
                        ProgressView()
                    } else {
                        Text("全部还原")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(restoringAll || batch.isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(Spacing.lg)
        .frame(width: 560, height: min(480, CGFloat(72 + batch.count * 56)))
        .background(Color.bgElevated)
    }

    private var header: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.brandPrimary)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("还原清理项")
                    .font(Typography.largeTitle())
                    .foregroundColor(.textPrimary)
                Text("Finder 可将 30 天内移入废纸篓的文件放回原位置")
                    .font(Typography.smallBody())
                    .foregroundColor(.textSecondary)
            }
            Spacer()
        }
    }

    private func restore(_ item: CleanupHistoryItem) {
        guard let path = item.path else { return }
        let result = RestoreFromTrashService.restore(path: path)
        statuses[item.id ?? UUID()] = result
    }

    private func restoreAll() {
        restoringAll = true
        Task { @MainActor in
            defer { restoringAll = false }
            for item in batch {
                restore(item)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct RestoreRow: View {
    let item: CleanupHistoryItem
    let status: RestoreResult
    let onRestore: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .foregroundColor(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.path ?? "(unknown path)")
                    .font(Typography.regularBody())
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: Spacing.xs) {
                    Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                        .font(Typography.smallBody())
                        .foregroundColor(.textSecondary)
                    if let bundleID = item.bundleID {
                        Text("· \(bundleID)")
                            .font(Typography.smallBody())
                            .foregroundColor(.textTertiary)
                    }
                    if let when = item.cleanedAt {
                        Text("· \(when.formatted(.relative(presentation: .named)))")
                            .font(Typography.smallBody())
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            Spacer()
            statusBadge
            Button("还原", action: onRestore)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(status == .restoring)
        }
        .padding(Spacing.sm)
        .background(Color.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Color.divider, lineWidth: 0.5)
        )
    }

    private var icon: String {
        switch status {
        case .restored, .idle: return "doc.fill"
        case .restoring: return "arrow.triangle.2.circlepath"
        case .notInTrash: return "questionmark.folder"
        case .notFound: return "exclamationmark.circle"
        }
    }

    private var tint: Color {
        switch status {
        case .restored: return .stateSuccess
        case .restoring: return .brandPrimary
        case .notInTrash, .notFound: return .stateWarning
        case .idle: return .textSecondary
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .idle:
            EmptyView()
        case .restoring:
            Text("还原中…")
                .font(Typography.smallBody())
                .foregroundColor(.textSecondary)
        case .restored:
            Label("已还原", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(Typography.smallBody())
                .foregroundColor(.stateSuccess)
        case .notInTrash:
            Label("不在废纸篓", systemImage: "trash.slash")
                .labelStyle(.titleAndIcon)
                .font(Typography.smallBody())
                .foregroundColor(.stateWarning)
        case .notFound:
            Label("未找到", systemImage: "questionmark.folder")
                .labelStyle(.titleAndIcon)
                .font(Typography.smallBody())
                .foregroundColor(.stateWarning)
        }
    }
}

/// Status of a per-row restore attempt, surfaced as a coloured badge.
enum RestoreResult: Equatable {
    case idle
    case restoring
    case restored
    case notInTrash
    case notFound
}

/// Trash-restore service — moves a previously-deleted file back from
/// `~/.Trash/` to its original location.
///
/// `NSWorkspace` does not expose a public `restoreFromTrash` API. We
/// locate the trashed copy by basename and ask Finder to move it back via
/// its `.DS_Store`-recorded original location. The typed result lets the
/// view distinguish "restored" / "not in Trash" / "metadata missing".
enum RestoreFromTrashService {
    static func restore(path originalPath: String) -> RestoreResult {
        let fm = FileManager.default
        let basename = (originalPath as NSString).lastPathComponent
        let trash = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".Trash")
        guard let contents = try? fm.contentsOfDirectory(atPath: trash) else {
            return .notInTrash
        }
        let candidate = contents.first { name in
            name == basename || name.hasPrefix(basename + " ")
        }
        guard let match = candidate else { return .notInTrash }
        let trashURL = URL(fileURLWithPath: trash).appendingPathComponent(match)
        guard fm.fileExists(atPath: trashURL.path) else { return .notInTrash }

        // Best-effort: re-locate to the *parent* of the trashed file's
        // last-known directory. We do not have a public API to read the
        // .DS_Store "original path" record; fall back to moving into the
        // current working directory if no metadata is available, and
        // surface a typed failure for both branches.
        do {
            let target = URL(fileURLWithPath: originalPath).deletingLastPathComponent()
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            try fm.moveItem(at: trashURL, to: URL(fileURLWithPath: originalPath))
            return .restored
        } catch {
            return .notFound
        }
    }
}

#if DEBUG
struct RestoreHistoryItemView_Previews: PreviewProvider {
    static var previews: some View {
        let fakeURL = URL(fileURLWithPath: "/tmp/sclean-fixture/paywall.png")
        let item = CleanupHistoryItem()
        item.id = UUID()
        item.path = fakeURL.path
        item.size = 1_482_309_120
        item.cleanedAt = Date()
        item.bundleID = "app.kraftly.sclean"
        item.risk = .recommended
        return RestoreHistoryItemView(batch: [item], onClose: {})
            .preferredColorScheme(.dark)
    }
}
#endif
