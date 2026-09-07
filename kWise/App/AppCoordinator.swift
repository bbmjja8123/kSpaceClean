import SwiftUI

/// The single navigation authority.
///
/// All navigation mutations (`appState.navigation`, presented sheets) go
/// through here so deep links, the icon rail, widget/intent opens, and the
/// menu bar cannot disagree. Views stop assigning `appState.navigation`
/// directly; they call ``navigate(to:)`` or a deep link.
@MainActor
public final class AppCoordinator: ObservableObject {
    public weak var appState: AppState?

    /// Presented sheet, if any (e.g. PaywallView triggered by the free tier).
    @Published public var presentedSheet: SheetKind?

    public enum SheetKind: Equatable {
        case paywall
    }

    public init(appState: AppState? = nil) {
        self.appState = appState
    }

    // MARK: - Deep links (kwise:// primary, kspaceclean:// alias)

    /// Handle an incoming deep link URL. Returns `true` when handled.
    @discardableResult
    public func handleDeepLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme,
              scheme == "kwise" || scheme == "kspaceclean"
        else { return false }
        // kwise://scan → host "scan"
        guard let host = url.host else { return false }

        switch host {
        case "scan":
            navigate(to: .scan)
            return true
        case "clean":
            navigate(to: .cleanup)
            return true
        case "smartcare":
            navigate(to: .smartCare)
            return true
        case "privacy":
            navigate(to: .privacy)
            return true
        case "health":
            navigate(to: .diskHealth)
            return true
        case "startup":
            navigate(to: .startupItems)
            return true
        case "uninstall":
            navigate(to: .appUninstall)
            return true
        case "shred":
            navigate(to: .shredder)
            return true
        case "galaxy":
            navigate(to: .galaxy)
            return true
        case "history":
            navigate(to: .history)
            return true
        case "settings":
            navigate(to: .settings)
            return true
        default:
            return false
        }
    }

    // MARK: - Navigation

    /// Navigate to a specific page.
    public func navigate(to item: AppState.NavigationItem) {
        appState?.navigation = item
    }

    /// Present the paywall sheet (free-tier gate — never ad hoc from views).
    public func presentPaywall() {
        presentedSheet = .paywall
    }
}

/// `.sheet(item:)` requires Identifiable; the kind itself is the identity
/// (there is at most one sheet of each kind on screen).
extension AppCoordinator.SheetKind: Identifiable {
    public var id: Self { self }
}
