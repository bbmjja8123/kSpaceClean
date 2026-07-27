import Foundation
import SwiftUI

// MARK: - OnboardingCoordinator

@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published var currentPage = 0

    let totalPages = 5
    var onComplete: (() -> Void)?

    // MARK: - Navigation

    /// Advance to the next page, or call onComplete on the last page.
    func next() {
        if currentPage < totalPages - 1 {
            currentPage += 1
        } else {
            onComplete?()
        }
    }

    // MARK: - FDA Actions

    /// Open System Preferences at the Full Disk Access pane.
    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Skip the FDA prompt and jump directly to the last page.
    func skipFDA() {
        currentPage = totalPages - 1
    }
}
