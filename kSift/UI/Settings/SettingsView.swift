import SwiftUI
import DesignSystem

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var store: StoreManager
    @State private var showPaywall = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title).bold()

            // Pro / Free tier section is always first — it's the user's
            // most actionable upgrade signal.
            proSection

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
        .task {
            viewModel.load()
            await store.loadProducts()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
    }

    @ViewBuilder
    private var proSection: some View {
        GlassPanel {
            HStack(spacing: 16) {
                Image(systemName: store.isPaidUser ? "checkmark.seal.fill" : "sparkles")
                    .font(.title)
                    .foregroundColor(store.isPaidUser ? .green : .brandPrimary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.isPaidUser ? "kSift Pro" : "Free Tier")
                        .font(.headline)
                    if store.isPaidUser {
                        Text("Unlimited cleanup, incremental index, and Finder Sync.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Cleaned \(formatBytes(store.freeTierBytesCleaned)) of \(formatBytes(StoreManager.freeCleanupQuotaBytes)) free quota.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if !store.isPaidUser {
                    Button("Upgrade") { showPaywall = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.brandPrimary)
                } else {
                    Button("Restore") {
                        Task { await store.restorePurchases() }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
        }
    }

    private func profileIcon(_ profile: ProfileType) -> String {
        switch profile {
        case .developer: return "hammer.fill"
        case .photographer: return "camera.fill"
        case .designer: return "person.fill"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}