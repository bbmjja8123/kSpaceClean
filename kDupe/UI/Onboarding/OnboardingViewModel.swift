import SwiftUI

@MainActor
public final class OnboardingViewModel: ObservableObject {
    @Published public var selectedProfile: ProfileType = .developer
    @Published public var customDirectories: [String] = []
    @Published public var customDirectoryStrings: String = ""
    @Published public var enablePerceptualScan = true
    @Published public var step = 0

    public func buildConfig() -> ProfileConfig {
        ProfileConfig(
            type: selectedProfile,
            customDirectories: customDirectoryStrings
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty },
            exclusions: selectedProfile.additionalExclusions,
            minFileSize: 1024,
            enablePerceptualScan: enablePerceptualScan
        )
    }
}
