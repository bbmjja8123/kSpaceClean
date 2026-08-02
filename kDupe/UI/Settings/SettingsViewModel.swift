import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var selectedProfile: ProfileType = .developer {
        didSet { syncIfReady() }
    }
    @Published var customDirectories: [String] = [] {
        didSet { syncIfReady() }
    }
    @Published var additionalExclusions: [String] = [] {
        didSet { syncIfReady() }
    }
    @Published var minFileSize: Int64 = 1024 {
        didSet { syncIfReady() }
    }
    @Published var enablePerceptual: Bool = true {
        didSet { syncIfReady() }
    }
    @Published var enableBuildArtifacts: Bool = true {
        didSet { syncIfReady() }
    }

    /// Suppresses the per-property didSet writes while `load()` is running so
    /// we don't persist six intermediate states between assigns.
    private var isLoading = false

    /// Live snapshot of the underlying config. Computed lazily — every read
    /// reflects the current published values.
    var currentConfig: ProfileConfig {
        ProfileConfig(
            type: selectedProfile,
            customDirectories: customDirectories,
            exclusions: additionalExclusions,
            minFileSize: minFileSize,
            enablePerceptualScan: enablePerceptual,
            enableBuildArtifacts: enableBuildArtifacts
        )
    }

    func load() {
        let config = ProfileConfigStore.load()
        isLoading = true
        selectedProfile = config.type
        customDirectories = config.customDirectories
        additionalExclusions = config.exclusions
        minFileSize = config.minFileSize
        enablePerceptual = config.enablePerceptualScan
        enableBuildArtifacts = config.enableBuildArtifacts
        isLoading = false
    }

    private func syncIfReady() {
        guard !isLoading else { return }
        ProfileConfigStore.save(currentConfig)
    }
}