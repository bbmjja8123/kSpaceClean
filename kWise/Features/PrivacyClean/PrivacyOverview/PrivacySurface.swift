import Foundation

/// One actionable privacy surface shown in the Privacy Overview.
///
/// The MAS power model (see `PowerScope`) replaces the old TCC.db reader:
/// instead of introspecting a private database kWise cannot legally or
/// reliably read, the overview lists only what kWise can actually act on,
/// plus guided deep links to System Settings for everything else.
public struct PrivacySurface: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// kWise can delete the underlying files itself (actionable).
        case cleanable
        /// kWise cannot act; deep-links to the relevant System Settings pane.
        case guidance
    }

    public let id: String
    public let kind: Kind
    /// Localizable key — the view resolves via `String(localized:)`.
    public let titleKey: String
    /// Localizable key describing what the surface holds.
    public let detailKey: String
    /// SF Symbol for the row.
    public let iconSystemName: String
    /// Settings deep link (`x-apple.systempreferences:`) for `.guidance` rows.
    public let settingsPath: String?

    public init(id: String,
                kind: Kind,
                titleKey: String,
                detailKey: String,
                iconSystemName: String,
                settingsPath: String? = nil) {
        self.id = id
        self.kind = kind
        self.titleKey = titleKey
        self.detailKey = detailKey
        self.iconSystemName = iconSystemName
        self.settingsPath = settingsPath
    }
}

extension PrivacySurface {
    /// Canonical catalog. `cleanable` rows are wired to real providers by
    /// the privacy scan pipeline; `guidance` rows deep-link out.
    public static let catalog: [PrivacySurface] = [
        PrivacySurface(id: "browser.traces",
                       kind: .cleanable,
                       titleKey: "privacy.surface.browserTraces.title",
                       detailKey: "privacy.surface.browserTraces.detail",
                       iconSystemName: "globe"),
        PrivacySurface(id: "recent.items",
                       kind: .cleanable,
                       titleKey: "privacy.surface.recentItems.title",
                       detailKey: "privacy.surface.recentItems.detail",
                       iconSystemName: "clock"),
        PrivacySurface(id: "quicklook.cache",
                       kind: .cleanable,
                       titleKey: "privacy.surface.quickLook.title",
                       detailKey: "privacy.surface.quickLook.detail",
                       iconSystemName: "eye"),
        PrivacySurface(id: "downloads.history",
                       kind: .cleanable,
                       titleKey: "privacy.surface.downloads.title",
                       detailKey: "privacy.surface.downloads.detail",
                       iconSystemName: "arrow.down.circle"),
        PrivacySurface(id: "permissions.fda",
                       kind: .guidance,
                       titleKey: "privacy.surface.fda.title",
                       detailKey: "privacy.surface.fda.detail",
                       iconSystemName: "lock.shield",
                       settingsPath: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"),
        PrivacySurface(id: "permissions.microphone",
                       kind: .guidance,
                       titleKey: "privacy.surface.microphone.title",
                       detailKey: "privacy.surface.microphone.detail",
                       iconSystemName: "mic",
                       settingsPath: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"),
        PrivacySurface(id: "permissions.camera",
                       kind: .guidance,
                       titleKey: "privacy.surface.camera.title",
                       detailKey: "privacy.surface.camera.detail",
                       iconSystemName: "video",
                       settingsPath: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"),
    ]
}
