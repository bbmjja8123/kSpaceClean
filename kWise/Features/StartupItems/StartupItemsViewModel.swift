// kWise/Features/StartupItems/StartupItemsViewModel.swift
import Foundation
import Combine
import PowerScope
import AppCatalogCore

/// Drives the 启动项 surface (M2, v2.0 Phase 5).
@MainActor
public final class StartupItemsViewModel: ObservableObject {
    @Published public private(set) var userItems: [LoginItemEntry] = []
    @Published public private(set) var systemItems: [LoginItemEntry] = []
    @Published public private(set) var malformedItems: [LaunchPlistParser.MalformedItem] = []
    /// Agent 用途推断 (v2.6 R2-4)：label → 已知产品名描述。
    @Published public private(set) var usageHints: [UUID: String] = [:]
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
            malformedItems = result.malformed
            // 用途推断：label 去常见后缀后反查 zh 映射表（219 条）。
            let store = MappingStore.loadFromBundledJSON()
            var hints: [UUID: String] = [:]
            let mappings = await store?.allMappings() ?? []
            for entry in result.user + result.system {
                // 用途推断走共享 API（ResidueExplainer.ownerHint）：与卸载
                // 残留解释同一条规则表，避免两处规则漂移。
                if let hint = ResidueExplainer.ownerHint(forLabel: entry.label, mappings: mappings) {
                    hints[entry.id] = hint
                }
            }
            usageHints = hints
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
