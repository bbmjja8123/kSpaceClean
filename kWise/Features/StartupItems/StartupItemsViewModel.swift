// kWise/Features/StartupItems/StartupItemsViewModel.swift
import Foundation
import Combine
import PowerScope

/// Drives the 启动项 surface (M2, v2.0 Phase 5).
@MainActor
public final class StartupItemsViewModel: ObservableObject {
    @Published public private(set) var userItems: [LoginItemEntry] = []
    @Published public private(set) var systemItems: [LoginItemEntry] = []
    @Published public private(set) var isScanning = false
    /// Row-local operation feedback (`entryID` → message).
    @Published public private(set) var messages: [UUID: String] = [:]

    private let scanner: StartupItemsScanner
    private let toggler: StartupItemToggler

    public init(scope: (any PowerScopeProviding)? = nil,
                persistence: PersistenceController? = nil) {
        self.scanner = StartupItemsScanner(scope: scope ?? AppScope.shared.scope)
        self.toggler = StartupItemToggler(persistence: persistence ?? .shared)
    }

    public func startScan() {
        guard !isScanning else { return }
        isScanning = true
        Task {
            let result = await scanner.scan()
            userItems = result.user
            systemItems = result.system
            isScanning = false
        }
    }

    /// Disable a user-level item (moves its plist to the Trash).
    public func disable(_ entry: LoginItemEntry) {
        Task {
            let ok = await toggler.disable(entry)
            messages[entry.id] = ok
                ? "已停用，可随时恢复"
                : "停用失败（系统级项目需手动处理）"
            startScan()
        }
    }

    /// Re-enable a previously disabled item (restores from the Trash).
    public func enable(_ entry: LoginItemEntry) {
        Task {
            let ok = await toggler.enable(entry)
            messages[entry.id] = ok
                ? "已恢复"
                : "恢复失败 — 项目可能已被清出废纸篓"
            startScan()
        }
    }

    public func clearMessage(for id: UUID) {
        messages.removeValue(forKey: id)
    }
}
