import AppIntents

struct DeepCleanIntent: AppIntent {
    static var title: LocalizedStringResource = "深度系统清理"
    static var description = IntentDescription("扫描并清理系统级残留（LaunchDaemons、LaunchAgents 等）")

    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult {
        guard await StoreManager.shared.isPro else {
            throw IntentError.proRequired
        }
        let engine = DeepCleanEngine()
        let groups = await engine.scanSystemWideResidues()
        return .result(value: "发现 \(groups.count) 组系统残留")
    }
}
