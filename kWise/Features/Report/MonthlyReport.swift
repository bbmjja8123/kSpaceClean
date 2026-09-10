// kWise/Features/Report/MonthlyReport.swift
//
// Mac 健康月报 (v2.0 Phase 7) — locally-generated monthly report from the
// cleanup history + disk samples: weekly freed bytes, top categories,
// streak, disk health grade, and the disk-full forecast. Zero network.
import SwiftUI
import DesignSystem

// MARK: - Generator

public struct MonthlyReport: Equatable {
    public struct WeekBucket: Equatable, Identifiable {
        public let id: Int
        public let label: String
        public let freedBytes: Int64
    }

    public struct TopCategory: Equatable, Identifiable {
        public let id: String
        public let title: String
        public let freedBytes: Int64
    }

    public let periodLabel: String
    public let totalFreedBytes: Int64
    public let totalCleanups: Int
    public let weekly: [WeekBucket]
    public let topCategories: [TopCategory]
    public let currentStreak: Int
    public let forecast: DiskForecastEngine.ForecastResult
    /// 本月最大 5 个已清理项 (v2.6 R2-5) — 每项可跳转大文件工具深挖。
    public let topCleanedFiles: [CleanedFile]
}

public struct CleanedFile: Equatable, Identifiable {
    public let name: String
    public let size: Int64
    public var id: String { name }
}

public enum ReportGenerator {

    /// Builds the report for the trailing 4 weeks (relative to `now`).
    public static func generate(history: [CleanupHistoryItem],
                                streak: StreakState,
                                samples: [DiskSample],
                                now: Date = Date(),
                                calendar: Calendar = .current) -> MonthlyReport {
        let monthAgo = calendar.date(byAdding: .day, value: -28, to: now) ?? now
        let recent = history.filter { ($0.cleanedAt ?? .distantPast) >= monthAgo }

        // Weekly buckets, oldest → newest.
        var buckets: [MonthlyReport.WeekBucket] = []
        for week in (0..<4).reversed() {
            let start = calendar.date(byAdding: .day, value: -7 * (week + 1), to: now)!
            let end = calendar.date(byAdding: .day, value: -7 * week, to: now)!
            let freed = recent
                .filter { ($0.cleanedAt ?? .distantPast) >= start && ($0.cleanedAt ?? .distantPast) < end }
                .reduce(Int64(0)) { $0 + $1.size }
            buckets.append(MonthlyReport.WeekBucket(
                id: week,
                label: week == 0 ? "本周" : "\(week) 周前",
                freedBytes: freed
            ))
        }

        // Top categories by freed size.
        let byCategory = Dictionary(grouping: recent) { $0.categoryID ?? "other" }
        let top = byCategory
            .map { key, rows in
                MonthlyReport.TopCategory(
                    id: key,
                    title: Self.friendlyCategory(key),
                    freedBytes: rows.reduce(Int64(0)) { $0 + $1.size }
                )
            }
            .sorted { $0.freedBytes > $1.freedBytes }
            .prefix(5)
            .map { $0 }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy 年 M 月"

        let topFiles: [CleanedFile] = recent
            .sorted { $0.size > $1.size }
            .prefix(5)
            .map { CleanedFile(name: URL(fileURLWithPath: $0.path ?? "").lastPathComponent, size: $0.size) }

        return MonthlyReport(
            periodLabel: formatter.string(from: now),
            totalFreedBytes: recent.reduce(Int64(0)) { $0 + $1.size },
            totalCleanups: recent.count,
            weekly: buckets,
            topCategories: top,
            currentStreak: streak.currentStreak,
            forecast: DiskForecastEngine.forecast(samples: samples, now: now, calendar: calendar),
            topCleanedFiles: topFiles
        )
    }

    private static func friendlyCategory(_ id: String) -> String {
        // Human-readable names; raw IDs only ever surface for unknown keys.
        switch id {
        case "system.cache": return "系统缓存"
        case "app.cache": return "应用缓存"
        case "web.junk": return "上网垃圾"
        case "mail.attachment": return "邮件附件"
        case "dev.junk": return "开发者垃圾"
        case "system.log": return "系统日志"
        default: return id
        }
    }
}

// MARK: - ViewModel

@MainActor
public final class MonthlyReportViewModel: ObservableObject {
    @Published public private(set) var report: MonthlyReport?
    @Published public private(set) var isLoading = false

    private let persistence: PersistenceController
    private let sampleStore = DiskSampleStore()
    private let streakStore = StreakStore()
    private let sampler = DiskUsageSampler(store: DiskSampleStore())

    public init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    public func refresh() {
        isLoading = true
        Task {
            // Opportunistic sample — opening the report is a usage moment.
            sampler.sample()
            let history = persistence.fetchHistory(limit: 0)
            let streak = streakStore.load()
            let samples = sampleStore.load()
            await MainActor.run { [weak self] in
                self?.report = ReportGenerator.generate(
                    history: history, streak: streak, samples: samples
                )
                self?.isLoading = false
            }
        }
    }
}

// MARK: - View

struct MonthlyReportView: View {
    @StateObject private var viewModel: MonthlyReportViewModel
    @EnvironmentObject var appState: AppState

    init(persistence: PersistenceController = .shared) {
        _viewModel = StateObject(wrappedValue: MonthlyReportViewModel(persistence: persistence))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                header
                if let report = viewModel.report {
                    heroStats(report)
                    weeklyChart(report)
                    topCategories(report)
                    topFiles(report)
                    forecastCard(report)
                } else if viewModel.isLoading {
                    LoadingStateView(title: "正在生成报告")
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(AppSpacing.xl)
        }
        .background(Color.bgPrimary)
        .onAppear { viewModel.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Mac 健康月报")
                .font(AppFont.title2)
                .foregroundStyle(Color.textPrimary)
            Text(viewModel.report?.periodLabel ?? "")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
            Text("数据全部在本机生成 · 磁盘采样来自使用 kWise 期间")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func heroStats(_ report: MonthlyReport) -> some View {
        HStack(spacing: AppSpacing.md) {
            statCard(icon: "trash", title: "本月释放", value: SmartCareHeroView.formatBytes(report.totalFreedBytes))
            statCard(icon: "sparkles", title: "清理次数", value: "\(report.totalCleanups)")
            statCard(icon: "flame", title: "连续打卡", value: "\(report.currentStreak) 天")
        }
    }

    private func statCard(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .foregroundStyle(Color.brandPrimary)
            Text(value)
                .font(AppFont.numberSize)
                .foregroundStyle(Color.textPrimary)
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    private func weeklyChart(_ report: MonthlyReport) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("每周释放")
                .font(AppFont.title3)
                .foregroundStyle(Color.textPrimary)
            HStack(alignment: .bottom, spacing: AppSpacing.md) {
                let maxBytes = max(report.weekly.map(\.freedBytes).max() ?? 1, 1)
                ForEach(report.weekly) { bucket in
                    VStack(spacing: AppSpacing.xs) {
                        RoundedRectangle(cornerRadius: AppRadius.sm)
                            .fill(Color.brandPrimary.opacity(0.7))
                            .frame(height: CGFloat(max(4, 90 * Double(bucket.freedBytes) / Double(maxBytes))))
                        Text(bucket.label)
                            .font(AppFont.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130)
        }
        .padding(AppSpacing.md)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    /// 本月清理的 Top5 大文件 + 「去处理」跳大文件工具 (v2.6 R2-5)。
    @ViewBuilder
    private func topFiles(_ report: MonthlyReport) -> some View {
        if !report.topCleanedFiles.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("本月清理的大文件 Top 5")
                    .font(AppFont.title3)
                    .foregroundColor(.textPrimary)
                ForEach(report.topCleanedFiles) { file in
                    HStack {
                        Image(systemName: "doc")
                            .foregroundColor(.brandPrimary)
                        Text(file.name)
                            .font(AppFont.body)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(SmartCareHeroView.formatBytes(file.size))
                            .font(AppFont.monoDigit)
                            .foregroundColor(.textSecondary)
                    }
                }
                Button {
                    appState.navigation = .largeOld
                } label: {
                    Label("去大文件工具继续深挖", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(AppFont.callout)
                }
                .buttonStyle(.bordered)
            }
            .padding(AppSpacing.md)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        }
    }

    @ViewBuilder
    private func topCategories(_ report: MonthlyReport) -> some View {
        if !report.topCategories.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("清理最多")
                    .font(AppFont.title3)
                    .foregroundStyle(Color.textPrimary)
                ForEach(report.topCategories) { category in
                    HStack {
                        Text(category.title)
                            .font(AppFont.body)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(SmartCareHeroView.formatBytes(category.freedBytes))
                            .font(AppFont.monoDigit)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .padding(AppSpacing.md)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        }
    }

    @ViewBuilder
    private func forecastCard(_ report: MonthlyReport) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("磁盘将满预测")
                .font(AppFont.title3)
                .foregroundStyle(Color.textPrimary)
            switch report.forecast {
            case .insufficientData:
                Text("样本不足 — 继续使用 kWise 几天后即可生成预测。")
                    .font(AppFont.body)
                    .foregroundStyle(Color.textSecondary)
            case .stable:
                Text("暂无明显的占满趋势（近期波动较大）。")
                    .font(AppFont.body)
                    .foregroundStyle(Color.textSecondary)
            case .filling(let days, _):
                Text("按当前趋势，预计约 \(days) 天后磁盘占满。建议提前清理大文件。")
                    .font(AppFont.body)
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }
}

#Preview {
    MonthlyReportView(persistence: PersistenceController(inMemory: true))
        .frame(width: 760, height: 560)
        .preferredColorScheme(.dark)
}
