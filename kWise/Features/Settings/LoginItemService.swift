// kWise/Features/Settings/LoginItemService.swift
//
// Launch-at-login for kWise itself (v2.0 Phase 1).
//
// `SMAppService.mainApp` (macOS 13+) is the only App-Store-legal mechanism:
// no helper, no `launchctl`, no `LSSharedFileList` writes to other apps.
// The previous Settings toggle had no implementation behind it — a silent
// lie (C-5). This service surfaces real status and real errors.
import ServiceManagement

/// Injectable seam over `SMAppService` so Settings can be tested with a fake.
@MainActor
public protocol LoginItemRegistering: Sendable {
    func register() throws
    func unregister() throws
    func status() -> SMAppService.Status
}

/// Production seam — talks to the real `SMAppService.mainApp`.
@MainActor
public struct SMAppServiceLoginItem: LoginItemRegistering {
    public init() {}

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    public func status() -> SMAppService.Status {
        SMAppService.mainApp.status
    }
}

/// Own-app login item state + transitions. Errors are surfaced, never
/// swallowed — a silent failure here is exactly the C-5 violation the
/// old hardcoded toggle was.
@MainActor
public final class LoginItemService: ObservableObject {
    /// Mirrors `SMAppService.mainApp.status`; drives the Settings row.
    @Published public private(set) var isEnabled: Bool
    /// Last transition error, for the Settings alert.
    @Published public private(set) var lastError: String?

    private let item: any LoginItemRegistering

    public init(item: any LoginItemRegistering = SMAppServiceLoginItem()) {
        self.item = item
        self.isEnabled = item.status() == .enabled
        self.lastError = nil
    }

    /// Enable or disable launch-at-login. `status` is refreshed from the
    /// system afterwards so the row never drifts from reality.
    public func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try item.register()
            } else {
                try item.unregister()
            }
            lastError = nil
        } catch {
            // Status is read back regardless — if SMAppService already
            // changed state, showing the stale toggle would be the lie.
            lastError = error.localizedDescription
        }
        isEnabled = item.status() == .enabled
    }

    /// Re-read the system status (call on appear — the user may have
    /// toggled it in System Settings > General > Login Items).
    public func refreshStatus() {
        isEnabled = item.status() == .enabled
    }

    /// Dismiss the error alert.
    public func acknowledgeError() {
        lastError = nil
    }
}
