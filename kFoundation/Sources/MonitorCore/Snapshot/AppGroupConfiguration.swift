import Foundation

/// App Group identifier shared across the app, Widget, Live Activity, and Intents
/// extensions. Must match the `com.apple.security.application-groups` entitlement.
public enum AppGroupConfiguration {
    public static let identifier = "group.app.kraftly.shared"

    /// Returns the shared container URL. Returns nil if the App Group is not provisioned
    /// (unsigned dev builds); callers must handle this gracefully.
    public static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Returns the directory that contains `snapshot.json`. Creates the directory if missing.
    public static func snapshotDirectory() -> URL? {
        guard let container = containerURL() else { return nil }
        let directory = container.appendingPathComponent("snapshots", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// URL of the canonical snapshot file inside the App Group.
    public static func snapshotURL() -> URL? {
        snapshotDirectory()?.appendingPathComponent("snapshot.json")
    }
}
