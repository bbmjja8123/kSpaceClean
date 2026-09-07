import AppIntents

enum IntentError: Swift.Error {
    case appNotFound
    case uninstallFailed
    case proRequired
}

// MARK: - Uninstall App Intent

struct UninstallAppIntent: AppIntent {
    static var title: LocalizedStringResource = "卸载 App"
    static var description = IntentDescription("卸载指定 App 及其残留文件")

    @Parameter(title: "App 名称")
    var appName: String

    /// When `true`, return a preview of what the uninstall *would* delete
    /// (size breakdown + residue list) without touching the file system.
    /// Drives the v1.x-B dry-run entry point from Shortcuts.
    @Parameter(title: "仅预览（不实际删除）", default: false)
    var dryRun: Bool

    func perform() async throws -> some IntentResult {
        let scanner = ResidueScanner()
        let apps = await scanner.scanAll()
        guard let app = apps.first(where: { $0.displayName == appName || $0.bundleID == appName }) else {
            throw IntentError.appNotFound
        }
        let mover = TrashMover()
        if dryRun {
            // Dry-run path: never touches the file system, never writes a
            // history record. Returns a human-readable preview string so
            // Shortcuts can display it in a notification or pass it on.
            let report = mover.dryRun(app: app, residues: app.residues)
            let bytes = ByteCountFormatter.string(fromByteCount: report.totalFreedBytes, countStyle: .file)
            let residueCount = report.residueSelection.count
            return .result(value: "预览：\(app.displayName) 将释放 \(bytes)（\(residueCount) 项残留）")
        }
        let result = await mover.moveToTrash(app: app, residues: app.residues)
        switch result {
        case .success:
            return .result(value: "已卸载 \(app.displayName)")
        case .failure:
            throw IntentError.uninstallFailed
        }
    }
}
