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

    func perform() async throws -> some IntentResult {
        let scanner = ResidueScanner()
        let apps = await scanner.scanAll()
        guard let app = apps.first(where: { $0.displayName == appName || $0.bundleID == appName }) else {
            throw IntentError.appNotFound
        }
        let mover = TrashMover()
        let result = await mover.moveToTrash(app: app, residues: app.residues)
        switch result {
        case .success:
            return .result(value: "已卸载 \(app.displayName)")
        case .failure:
            throw IntentError.uninstallFailed
        }
    }
}
