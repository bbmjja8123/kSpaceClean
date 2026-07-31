// kSpaceClean/Features/Common/Components/DiskUsageBar.swift
import SwiftUI
import DesignSystem
import CommonUtils

/// Snapshot of the current volume's storage state.
///
/// `DiskUsage` is a `Sendable` value type that captures the four numbers a
/// UI surface needs to render a storage indicator: total, used, and free
/// bytes plus the optional per-bucket sizes (system, cache, projected
/// cleanup savings). Construct it with ``current()`` to read the live
/// values from the home volume's `URLResourceValues` (no privileged
/// helpers — the same query the system uses for the Finder "Get Info"
/// window).
///
/// The struct stays `public` so right-panel tabs, the toolbar, the
/// widget, and the menu bar can all share a single source of truth
/// without dragging the rest of the app shell into the model.
public struct DiskUsage: Sendable {
    public let totalSpace: Int64
    public let usedSpace: Int64
    public let freeSpace: Int64
    public let systemSize: Int64
    public let cacheSize: Int64
    public let cleanupSavings: Int64

    public static func current() -> DiskUsage {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? home.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else {
            return DiskUsage(totalSpace: 0, usedSpace: 0, freeSpace: 0, systemSize: 0, cacheSize: 0, cleanupSavings: 0)
        }
        let totalInt = Int64(total)
        let freeInt = Int64(free)
        return DiskUsage(
            totalSpace: totalInt,
            usedSpace: totalInt - freeInt,
            freeSpace: freeInt,
            systemSize: 0,
            cacheSize: 0,
            cleanupSavings: 0
        )
    }
}

/// Compact horizontal disk-usage bar used at the bottom of the main
/// surface.
///
/// Renders a `used / total` text label on the left, a 4-pt capsule bar
/// in the middle (green below 70% used, yellow between 70-90%, red
/// above 90%), and a `total` text label on the right. The bar is
/// driven by ``DiskUsage/current()`` and refreshes on appear and
/// whenever `scanViewModel.scanDidComplete` flips to `true` so a
/// fresh scan immediately reflects in the storage indicator.
struct DiskUsageBar: View {
    @ObservedObject var scanViewModel: ScanViewModel
    @State private var diskUsage = DiskUsage.current()

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text("\u{5DF2}\u{7528} \(FileSizeFormatter.abbreviated(from: diskUsage.usedSpace))")
                .font(AppFont.caption).foregroundColor(.textSecondary)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.separatorColor.opacity(0.3)).frame(height: 4)
                    let ratio = diskUsage.totalSpace > 0 ? min(CGFloat(diskUsage.usedSpace) / CGFloat(diskUsage.totalSpace), 1.0) : 0
                    Capsule().fill(ratio > 0.9 ? Color.danger : ratio > 0.7 ? Color.warning : Color.success)
                        .frame(width: geo.size.width * ratio, height: 4)
                }
            }.frame(width: 100)

            Text("\u{5171} \(FileSizeFormatter.abbreviated(from: diskUsage.totalSpace))")
                .font(AppFont.caption).foregroundColor(.textSecondary)
        }
        .onAppear {
            diskUsage = DiskUsage.current()
        }
        .onReceive(scanViewModel.$scanDidComplete) { _ in
            diskUsage = DiskUsage.current()
        }
    }
}
