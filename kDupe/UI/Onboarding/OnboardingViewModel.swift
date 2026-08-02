import SwiftUI

@MainActor
public final class OnboardingViewModel: ObservableObject {
    @Published public var selectedProfile: ProfileType = .developer
    @Published public var customDirectories: [String] = []
    @Published public var customDirectoryStrings: String = ""
    @Published public var enablePerceptualScan = true
    @Published public var enableBuildArtifacts = true
    @Published public var step = 0

    public init() {}

    /// Build the config from the user's selections. `exclusions` is left
    /// empty here — `ScanOrchestrator` already merges in
    /// `selectedProfile.additionalExclusions` so storing them again would
    /// double the rules (harmless but wasteful).
    public func buildConfig() -> ProfileConfig {
        ProfileConfig(
            type: selectedProfile,
            customDirectories: customDirectoryStrings
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty },
            exclusions: [],
            minFileSize: 1024,
            enablePerceptualScan: enablePerceptualScan,
            enableBuildArtifacts: enableBuildArtifacts
        )
    }

    /// Persist via the shared store so the next launch's settings reflect
    /// the user's onboarding choices.
    public func persist() {
        ProfileConfigStore.save(buildConfig())
    }
}