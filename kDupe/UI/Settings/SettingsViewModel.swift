import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var selectedProfile: ProfileType = .developer
    @Published var customDirectories: [String] = []
    @Published var additionalExclusions: [String] = []
    @Published var minFileSize: Int64 = 1024
    @Published var enablePerceptual: Bool = true
    @Published var enableBuildArtifacts: Bool = true

    func save() {
        UserDefaults.standard.set(selectedProfile.rawValue, forKey: "selectedProfile")
        UserDefaults.standard.set(minFileSize, forKey: "minFileSize")
        UserDefaults.standard.set(enablePerceptual, forKey: "enablePerceptual")
        UserDefaults.standard.set(enableBuildArtifacts, forKey: "enableBuildArtifacts")
    }

    func load() {
        if let raw = UserDefaults.standard.string(forKey: "selectedProfile"),
           let profile = ProfileType(rawValue: raw) {
            selectedProfile = profile
        }
        minFileSize = UserDefaults.standard.object(forKey: "minFileSize") as? Int64 ?? 1024
        enablePerceptual = UserDefaults.standard.bool(forKey: "enablePerceptual")
        enableBuildArtifacts = UserDefaults.standard.bool(forKey: "enableBuildArtifacts")
    }
}
