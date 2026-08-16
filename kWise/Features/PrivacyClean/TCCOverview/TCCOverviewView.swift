import SwiftUI
import DesignSystem
import AppKit

/// TCC privacy overview grid (v1.5 Phase C Task 9).
///
/// Renders one card per TCC service (Camera, Full Disk Access, …).
/// When TCC.db is unreadable (Q8 "B" 兜底), cards surface a "需要完整磁盘访问"
/// hint and the view shows an "打开系统设置" CTA so the user can grant FDA.
///
/// - SeeAlso: ``TCCReader``, ``TCCOverviewViewModel``,
///   `docs/superpowers/plans/2026-08-09-kwise-v1.5-plan.md` Task 9
public struct TCCOverviewView: View {
    @StateObject private var viewModel = TCCOverviewViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: AppSpacing.md),
        GridItem(.flexible(), spacing: AppSpacing.md)
    ]

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            headerView
            if viewModel.needsFullDiskAccess {
                fdaPrompt
            }
            gridView
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
        .task {
            await viewModel.refresh()
        }
    }

    // MARK: - Sub-views

    private var headerView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("权限概览")
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                statusLine
            }
            Spacer()
            Button("刷新") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isLoading)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if viewModel.isLoading {
            Text("加载中…")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
        } else if let refreshedAt = viewModel.lastRefreshedAt {
            Text("更新于 \(refreshedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
        } else {
            Text("本地数据 — 来自 TCC.db 与 kFoundation 缓存")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var fdaPrompt: some View {
        GlassPanel {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.brandAccent)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("需要完整磁盘访问")
                        .font(AppFont.title3)
                        .foregroundStyle(Color.textPrimary)
                    Text("授权后可读取 TCC 数据库，显示每个类别的应用授权详情。")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Button("打开系统设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(AppSpacing.md)
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppSpacing.md) {
                ForEach(viewModel.categories) { category in
                    categoryCard(category)
                }
            }
        }
    }

    private func categoryCard(_ category: PermissionCategory) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack {
                    Image(systemName: iconForCategory(category))
                        .font(.system(size: 18))
                        .foregroundStyle(Color.brandPrimary)
                    Spacer()
                    if !category.isFallback {
                        Text("\(category.grantedAppCount)")
                            .font(AppFont.title3)
                            .foregroundStyle(category.grantedAppCount > 0
                                             ? Color.brandPrimary
                                             : Color.textSecondary)
                    }
                }
                Text(category.title)
                    .font(AppFont.title3)
                    .foregroundStyle(Color.textPrimary)
                Text(category.friendlySummary)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.md)
        }
    }

    /// SF Symbol for each TCC service — chosen for instant visual recognizability
    /// rather than literal accuracy. The mapping can be refined in a follow-up.
    private func iconForCategory(_ category: PermissionCategory) -> String {
        switch category.service {
        case "kTCCServiceAllFiles":                 return "externaldrive.fill.badge.checkmark"
        case "kTCCServiceAccessibility":            return "figure.roll"
        case "kTCCServiceScreenCapture":            return "rectangle.dashed.badge.record"
        case "kTCCServiceCamera":                   return "camera.fill"
        case "kTCCServiceMicrophone":               return "mic.fill"
        case "kTCCServiceLocation":                 return "location.fill"
        case "kTCCServicePhotos":                   return "photo.fill"
        case "kTCCServiceAddressBook":              return "person.crop.circle.fill"
        case "kTCCServiceCalendar", "kTCCServiceReminders":
            return "calendar"
        case "kTCCServiceBluetooth":                return "personalhotspot"
        case "kTCCServiceSystemPolicyDesktopFolder": return "folder.fill"
        default:                                    return "lock.shield.fill"
        }
    }
}

#if DEBUG
#Preview {
    TCCOverviewView()
        .frame(width: 720, height: 600)
}
#endif