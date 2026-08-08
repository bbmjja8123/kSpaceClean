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
