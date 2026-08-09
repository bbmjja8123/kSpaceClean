import SwiftUI
import AppKit

@MainActor
final class VaultViewModel: ObservableObject {
    @Published var items: [VaultItem] = []
    @Published var totalSize: Int64 = 0
    @Published var errorMessage: String?
    @Published var isProcessing = false
    @Published var isLoading = false

    private let manager: VaultManager

    init(manager: VaultManager = VaultManager()) {
        self.manager = manager
    }

    /// Count of items that have already passed their 30-day expiry window.
    /// Drives the "X items ready to purge" banner; clicking Purge expired
    /// clears these specifically.
    var expiredCount: Int {
        let now = Date()
        return items.filter { $0.expiresAt <= now }.count
    }

    /// Earliest upcoming expiry (i.e. the item that will be purged next if
    /// the user does nothing). `nil` when no items are vaulted.
    var nextExpiry: Date? {
        let future = items
            .filter { $0.expiresAt > Date() }
            .map(\.expiresAt)
            .min()
        return future
    }

    /// Human-readable "X days, Y hours until next auto-purge" countdown.
    /// `nil` when no items are pending purge.
    var nextExpiryFormatted: String? {
        guard let nextExpiry else { return nil }
        let interval = nextExpiry.timeIntervalSinceNow
        guard interval > 0 else { return nil }
        let days = Int(interval) / 86_400
        let hours = (Int(interval) % 86_400) / 3_600
        if days > 0 {
            return String(format: NSLocalizedString("%dd %dh", comment: "Days+hours countdown"), days, hours)
        } else if hours > 0 {
            return String(format: NSLocalizedString("%dh", comment: "Hours countdown"), hours)
        } else {
            return NSLocalizedString("<1h", comment: "Less-than-1h countdown")
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let raw = try await manager.vaultItems()
            items = raw.sorted { $0.vaultedAt > $1.vaultedAt }
            totalSize = try await manager.vaultSize()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func restore(_ item: VaultItem) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            _ = try await manager.restore(itemID: item.id)
            await load()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func purgeExpired() async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            _ = try await manager.deleteExpired()
            await load()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    func revealInFinder(_ item: VaultItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.vaultPath])
    }

    private static func message(for error: Error) -> String {
        if let vaultError = error as? VaultError {
            return localizedMessage(for: vaultError)
        }
        return error.localizedDescription
    }

    private static func localizedMessage(for error: VaultError) -> String {
        switch error {
        case .vaultUnavailable(let detail):
            return String(format: NSLocalizedString("Vault unavailable: %@", comment: "Vault unavailable"), detail)
        case .copyFailed(let url, let detail):
            return String(format: NSLocalizedString("Failed to copy %@ into the vault: %@", comment: "Copy failed"),
                          url.lastPathComponent, detail)
        case .hashMismatch(let url):
            return String(format: NSLocalizedString("SHA-256 mismatch for %@", comment: "Hash mismatch"),
                          url.lastPathComponent)
        case .vaultItemNotFound:
            return NSLocalizedString("This vault item no longer exists.", comment: "Vault item not found")
        case .vaultCopyMissing(let url):
            return String(format: NSLocalizedString("The vault copy of %@ is missing.", comment: "Vault copy missing"),
                          url.lastPathComponent)
        case .restoreTargetExists(let url):
            return String(format: NSLocalizedString("Cannot restore: %@ already exists.", comment: "Restore target exists"),
                          url.path)
        case .restoreFailed(let url, let detail):
            return String(format: NSLocalizedString("Failed to restore %@: %@", comment: "Restore failed"),
                          url.lastPathComponent, detail)
        }
    }
}
