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
    /// How aggressively similar images are grouped (strict/normal/loose).
    @Published var similarityPreset: SimilarityPreset = .normal {
        didSet { syncIfReady() }
    }
    /// Files at or above this size appear in the Large Files results.
    @Published var largeFileSizeThreshold: Int64 = 100 * 1024 * 1024 {
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
            enableBuildArtifacts: enableBuildArtifacts,
            selectionStrategy: selectionStrategy,
            similarityPreset: similarityPreset,
            largeFileSizeThreshold: largeFileSizeThreshold
        )
    }

    /// Auto Keep strategy — read-only mirror here (edited from the
    /// results screen's Smart Select menu); still round-tripped on save.
    var selectionStrategy: SelectionStrategy = .keepNewest

    func load() {
        let config = ProfileConfigStore.load()
        isLoading = true
        selectedProfile = config.type
        customDirectories = config.customDirectories
        additionalExclusions = config.exclusions
        minFileSize = config.minFileSize
        enablePerceptual = config.enablePerceptualScan
        enableBuildArtifacts = config.enableBuildArtifacts
        selectionStrategy = config.selectionStrategy
        similarityPreset = config.similarityPreset
        largeFileSizeThreshold = config.largeFileSizeThreshold
        isLoading = false
    }

    private func syncIfReady() {
        guard !isLoading else { return }
        ProfileConfigStore.save(currentConfig)
    }
}