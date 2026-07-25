import SwiftUI
import DesignSystem

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title).bold()

            Form {
                Section("Profile") {
                    Picker("Scan Profile", selection: $viewModel.selectedProfile) {
                        ForEach(ProfileType.allCases, id: \.self) { profile in
                            Label(profile.title, systemImage: profileIcon(profile))
                                .tag(profile)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Section("Scan Options") {
                    VStack(alignment: .leading) {
                        Text("Min file size: \(formatBytes(viewModel.minFileSize))")
                        Slider(value: Binding(
                            get: { Double(viewModel.minFileSize) },
                            set: { viewModel.minFileSize = Int64($0) }
                        ), in: 256...10_485_760, step: 256)
                    }

                    Toggle("Enable perceptual similarity (macOS 14+)",
                          isOn: $viewModel.enablePerceptual)
                    Toggle("Scan build artifacts",
                          isOn: $viewModel.enableBuildArtifacts)
                }

                Section("Scan Directories") {
                    ForEach(viewModel.customDirectories, id: \.self) { dir in
                        HStack {
                            Text(dir)
                            Spacer()
                            Button("Remove") {
                                viewModel.customDirectories.removeAll { $0 == dir }
                            }
                        }
                    }
                    Button("Add Directory") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        guard panel.runModal() == .OK, let url = panel.url else { return }
                        viewModel.customDirectories.append(url.path)
                    }
                }
            }
        }
        .padding()
        .task { viewModel.load() }
        .onChange(of: viewModel.selectedProfile) { _ in viewModel.save() }
    }

    private func profileIcon(_ profile: ProfileType) -> String {
        switch profile {
        case .developer: return "hammer.fill"
        case .photographer: return "camera.fill"
        case .simple: return "person.fill"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
