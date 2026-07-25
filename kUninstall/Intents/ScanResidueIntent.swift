import AppIntents

struct ScanResidueIntent: AppIntent {
    static var title: LocalizedStringResource = "扫描 App 残留"
    static var description = IntentDescription("扫描指定 App 的残留文件")

    @Parameter(title: "App 名称")
    var appName: String

    func perform() async throws -> some IntentResult {
        let detector = ResidueDetector()
        let residues = await detector.detectResidues(bundleID: appName, appName: appName)
        let totalSize = residues.reduce(0) { $0 + $1.sizeBytes }
        return .result(
            value: "发现 \(residues.count) 项残留，共 \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))"
        )
    }
}
