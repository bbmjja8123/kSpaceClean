import SwiftUI
import DesignSystem

/// Loads the recent-scan reassurance data for the idle dashboard.
/// Repository injectable so previews/tests can stub it.
@MainActor
final class IdleDashboardModel: ObservableObject {
    struct RecentScan: Identifiable {
        let id: UUID
        let timestamp: Date
        let groupsFound: Int
        let wasteBytes: Int64
    }

    @Published private(set) var recentScans: [RecentScan] = []
    @Published private(set) var lastScanSummary: RecentScan?

    private let repository: DuplicateRepositoryProtocol

    init(repository: DuplicateRepositoryProtocol = DuplicateRepositoryCoreData()) {
        self.repository = repository
    }

    /// Pulls the newest persisted scan records. Runs detached so the
    /// Core Data fetch never blocks the first frame of the idle screen.
    func loadRecentScans() {
        let repository = self.repository
        Task.detached(priority: .userInitiated) { [weak self] in
            let records = (try? await repository.loadScanRecords()) ?? []
            let recent = records.prefix(3).map { record in
                RecentScan(
                    id: record.id,
                    timestamp: record.timestamp,
                    groupsFound: record.totalDuplicatesFound,
                    wasteBytes: record.totalWasteSize
                )
            }
            await MainActor.run {
                self?.recentScans = recent
                self?.lastScanSummary = recent.first
            }
        }
    }
}

/// The idle-screen hero: reassurance from the last scan, one-tap profile
/// presets, and the scan-range preview — everything the user needs to
/// start with confidence instead of a bare magnifying-glass glyph.
struct IdleDashboardView: View {
    let previewDirectories: [String]
    /// Called with the profile the user tapped, so the parent can persist
    /// the choice and start a scan scoped to that profile.
    let onStartWithProfile: (ProfileType) -> Void
    let onStartScan: () -> Void

    @StateObject private var model = IdleDashboardModel()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                hero
                presetCards
                if let last = model.lastScanSummary {
                    lastScanCard(last)
                }
                ScanRangePreview(directories: previewDirectories)
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onAppear { model.loadRecentScans() }
    }

    private var hero: some View {
        VStack(spacing: AppSpacing.sm) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.brandPrimary, Color.brandSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("Ready to Scan")
                .font(.title).bold()
            Text("Find duplicate, similar, and oversized files — then reclaim the space in one tap.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: onStartScan) {
                Label("Start Scan", systemImage: "play.fill")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
            .controlSize(.large)
            .padding(.top, AppSpacing.xs)
        }
    }

    /// One-tap profile presets — the profiles used to live only in
    /// Settings; surfacing them here shortens the first-run path to a
    /// completed scan to a single click.
    private var presetCards: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Quick Start")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: AppSpacing.sm)], spacing: AppSpacing.sm) {
                ForEach(ProfileType.allCases, id: \.self) { profile in
                    Button {
                        onStartWithProfile(profile)
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Image(systemName: iconFor(profile))
                                .font(.title3)
                                .foregroundColor(.brandPrimary)
                            Text(profile.title)
                                .font(.callout).bold()
                                .foregroundColor(.textPrimary)
                            Text(descriptionFor(profile))
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppSpacing.md)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.lg)
                                .stroke(Color.brandPrimary.opacity(0.18), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(String(
                        format: NSLocalizedString("Scan with the %@ profile", comment: "Profile preset card tooltip"),
                        profile.title
                    ))
                    .accessibilityLabel(Text(String(
                        format: NSLocalizedString("Scan with the %@ profile", comment: "Profile preset card tooltip"),
                        profile.title
                    )))
                }
            }
        }
    }

    private func lastScanCard(_ scan: IdleDashboardModel.RecentScan) -> some View {
        GlassPanel {
            HStack(spacing: AppSpacing.md) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundColor(.success)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Last scan")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    Text(String(
                        format: NSLocalizedString("Found %lld duplicates · %@ reclaimable", comment: "Last-scan reassurance line"),
                        scan.groupsFound,
                        ByteCountFormatter.string(fromByteCount: scan.wasteBytes, countStyle: .file)
                    ))
                    .font(.callout)
                    .foregroundColor(.textPrimary)
                    Text(Self.dateFormatter.string(from: scan.timestamp))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }
            .padding(AppSpacing.lg)
        }
    }

    private func iconFor(_ profile: ProfileType) -> String {
        switch profile {
        case .developer: return "terminal"
        case .photographer: return "camera"
        case .designer: return "person"
        case .custom: return "slider.horizontal.3"
        }
    }

    private func descriptionFor(_ profile: ProfileType) -> String {
        switch profile {
        case .developer: return NSLocalizedString("Projects, build artifacts, dev directories", comment: "Preset card description")
        case .photographer: return NSLocalizedString("Photos, RAW files, creative assets", comment: "Preset card description")
        case .designer: return NSLocalizedString("Desktop, downloads, documents", comment: "Preset card description")
        case .custom: return NSLocalizedString("Only the folders you choose", comment: "Preset card description")
        }
    }
}
