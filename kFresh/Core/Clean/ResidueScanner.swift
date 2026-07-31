import Foundation

actor ResidueScanner {
    private let appCatalog = AppCatalogService()
    private let residueDetector = ResidueDetector(ruleStore: nil)

    func scanAll() async -> [InstalledApp] {
        let apps = await appCatalog.scan()
        return await withTaskGroup(of: InstalledApp.self) { group in
            for app in apps {
                group.addTask {
                    var mutable = app
                    let residues = await self.residueDetector.detectResidues(
                        bundleID: app.bundleID,
                        appName: app.displayName,
                        appURL: app.url
                    )
                    mutable.residues = residues
                    return mutable
                }
            }
            var result = [InstalledApp]()
            for await app in group {
                result.append(app)
            }
            return result.sorted { $0.displayName < $1.displayName }
        }
    }
}
