import Foundation

/// Scans the user's installed apps and enriches each with its associated residue files.
///
/// The scanner is a thin orchestrator over two collaborators:
///
/// - `AppCatalogService` enumerates installed `.app` bundles.
/// - `ResidueDetector` looks up each app's residue paths using the
///   injected `BundleRuleStore` first, then falls back to built-in
///   path templates.
///
/// **C-2 fix**: pre-fix the scanner was constructed with
/// `ResidueDetector(ruleStore: nil)` and every app fell through to the
/// template branch, silently missing the curated `cask_rules.json`
/// entries for popular apps. Post-fix the scanner accepts an optional
/// `ruleStore`; if `nil`, it loads the bundled
/// `cask_rules.json` via ``BundleRuleStore/loadFromBundledJSON(named:in:)``
/// at construction time so the production scan path picks up curated
/// rules without an explicit init argument.
///
/// Tests inject a custom `ruleStore` via ``init(ruleStore:appCatalog:)``
/// to assert deterministic behaviour without depending on the bundled
/// resource.
actor ResidueScanner {
    private let appCatalog: AppCatalogService
    private let residueDetector: ResidueDetector

    /// Default production initializer: loads `cask_rules.json` from the
    /// main bundle so the curated rules apply. When the bundled JSON
    /// is unavailable (e.g. during very early launch before the bundle
    /// is set up), the scanner still works via the template branch.
    init() {
        self.appCatalog = AppCatalogService()
        let store = BundleRuleStore.loadFromBundledJSON() ?? nil
        self.residueDetector = ResidueDetector(ruleStore: store)
    }

    /// Test-only initializer: lets a test inject a pre-built
    /// `BundleRuleStore` and (optionally) a custom `AppCatalogService`
    /// so the assertion path is fully deterministic. Production code
    /// should always use ``init()``.
    /// - Parameters:
    ///   - ruleStore: Curated rules for the residue detector. Pass
    ///     `nil` to fall back to template-only detection.
    ///   - appCatalog: App catalog service (default: real one).
    init(ruleStore: BundleRuleStore?, appCatalog: AppCatalogService = AppCatalogService()) {
        self.appCatalog = appCatalog
        self.residueDetector = ResidueDetector(ruleStore: ruleStore)
    }

    /// Returns every installed app with its residues populated.
    /// - Returns: Apps sorted by display name, each carrying its
    ///   detected residue set (curated rule paths first, then template
    ///   fallbacks).
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

    /// Test seam: runs the residue detector for one app without
    /// enumerating the catalog. Production callers should use
    /// ``scanAll()``; tests use this to assert the residue path
    /// produced by a known bundle ID without setting up a fake
    /// `AppCatalogService`.
    /// - Parameters:
    ///   - bundleID: Reverse-DNS bundle identifier.
    ///   - appName: Display name for template-branch path templates.
    ///   - appURL: Location of the `.app` bundle.
    /// - Returns: Residue files for this app.
    func detectResiduesForApp(bundleID: String, appName: String, appURL: URL) async -> [ResidueFile] {
        await residueDetector.detectResidues(bundleID: bundleID, appName: appName, appURL: appURL)
    }
}