import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

/// Publishes kMonitor quick actions to Spotlight so users can launch them by
/// typing things like "kMonitor disk" into the macOS menu-bar search field.
///
/// Privacy:
///
/// - We deliberately do NOT index per-process names, file paths, network
///   addresses, or any other user-identifying data. Spotlight is a system
///   service that ships with the OS and can sync to iCloud; only metadata
///   about kMonitor's own commands is safe to publish.
/// - The `uniqueIdentifier` for each item is stable so re-indexing replaces
///   the existing entries rather than leaving stale duplicates behind.
@available(macOS 13.0, *)
@MainActor
public final class KMonitorSpotlightIndexer {
    /// Domain that groups all kMonitor items inside Spotlight's index.
    public static let domainIdentifier = "app.kraftly.kmonitor.spotlight"

    public init() {}

    /// Rebuilds the Spotlight index from scratch.
    ///
    /// `deleteAll` is the safest pattern for an app that exposes a small,
    /// well-known set of actions: any removed action is automatically cleaned
    /// up on the next launch instead of lingering in the system index.
    public func reindex() async {
        let items = buildItems()
        do {
            try await CSSearchableIndex.default()
                .deleteSearchableItems(withDomainIdentifiers: [Self.domainIdentifier])
        } catch {
            // Spotlight may not be available on every machine; non-fatal.
        }
        do {
            try await CSSearchableIndex.default().indexSearchableItems(items)
        } catch {
            // Non-fatal; the indexer will retry on the next launch.
        }
    }

    /// Builds the searchable items exposed to Spotlight.
    ///
    /// `kMonitor` itself + one item per free action + one item per Pro action.
    /// Descriptions are short so they fit on the Spotlight card.
    private func buildItems() -> [CSSearchableItem] {
        var items: [CSSearchableItem] = []

        // The app itself. Tapping it launches kMonitor.
        let appItem = CSSearchableItem(
            uniqueIdentifier: "app.kraftly.kmonitor",
            domainIdentifier: Self.domainIdentifier,
            attributeSet: makeAttributes(
                title: "kMonitor",
                description: "Menu-bar metrics for CPU, memory, disk, and network.",
                keywords: ["kmonitor", "kraftly", "monitor", "metrics"]
            )
        )
        items.append(appItem)

        // Free actions.
        items.append(actionItem(
            id: "intent.queryMetric",
            title: "Ask kMonitor for a metric",
            description: "Returns the latest CPU, memory, disk, or network value.",
            keywords: ["cpu", "memory", "disk", "network", "metric"]
        ))
        items.append(actionItem(
            id: "intent.openDashboard",
            title: "Open kMonitor Dashboard",
            description: "Bring the kMonitor window to the front.",
            keywords: ["open", "dashboard", "window"]
        ))
        items.append(actionItem(
            id: "intent.startMonitoring",
            title: "Start kMonitor Monitoring",
            description: "Begin background sampling of system metrics.",
            keywords: ["start", "monitor", "background"]
        ))
        items.append(actionItem(
            id: "intent.showDiskUsage",
            title: "Show Disk Usage",
            description: "Reports current percentage of the boot disk in use.",
            keywords: ["disk", "usage", "storage"]
        ))

        // Pro actions. We still index them so users can discover them.
        items.append(actionItem(
            id: "intent.stopMonitoring",
            title: "Stop kMonitor Monitoring",
            description: "Pause background sampling. Requires kMonitor Pro.",
            keywords: ["stop", "monitor", "pause", "pro"]
        ))
        items.append(actionItem(
            id: "intent.showTopProcesses",
            title: "Show Top Processes",
            description: "List the five highest-CPU processes. Requires kMonitor Pro.",
            keywords: ["process", "cpu", "top", "pro"]
        ))
        items.append(actionItem(
            id: "intent.showNetworkRate",
            title: "Show Network Rate",
            description: "Reports current network throughput. Requires kMonitor Pro.",
            keywords: ["network", "rate", "throughput", "pro"]
        ))
        items.append(actionItem(
            id: "intent.exportDiagnostics",
            title: "Export Diagnostics",
            description: "Create a local diagnostics archive. Requires kMonitor Pro.",
            keywords: ["diagnostics", "export", "log", "pro"]
        ))

        return items
    }

    /// Builds a single action `CSSearchableItem` from a title + description.
    private func actionItem(
        id: String,
        title: String,
        description: String,
        keywords: [String]
    ) -> CSSearchableItem {
        CSSearchableItem(
            uniqueIdentifier: id,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: makeAttributes(
                title: title,
                description: description,
                keywords: keywords
            )
        )
    }

    /// Builds the attribute set. Centralized so every item uses the same
    /// content type and rating settings.
    private func makeAttributes(
        title: String,
        description: String,
        keywords: [String]
    ) -> CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: UTType.application)
        attributes.title = title
        attributes.contentDescription = description
        attributes.keywords = keywords
        // We don't want Spotlight to treat our action items as user content
        // for ranking purposes; this keeps the app-item the strongest match
        // for the bare "kmonitor" query.
        attributes.rating = 0
        return attributes
    }
}