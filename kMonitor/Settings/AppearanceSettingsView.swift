import SwiftUI
import DesignSystem

/// Appearance settings pane: theme mode picker and sparkline color theme
/// selector with live color swatches. All mutations go through
/// `SettingsViewModel` so changes are persisted immediately.
struct AppearanceSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                themeModePicker
            } header: {
                Text(String(localized: "Theme"))
            } footer: {
                Text(String(localized: "System follows your macOS appearance setting."))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Section {
                sparklineThemePicker
            } header: {
                Text(String(localized: "Sparkline Colors"))
            } footer: {
                Text(String(localized: "Controls the line and fill colors of sparkline charts in the menu bar."))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 4)
    }

    // MARK: - Theme mode picker

    private var themeModePicker: some View {
        Picker(String(localized: "Mode"), selection: Binding(
            get: { viewModel.themeMode },
            set: { viewModel.setThemeMode($0) }
        )) {
            ForEach(ThemeMode.allCases, id: \.self) { mode in
                Text(label(for: mode)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func label(for mode: ThemeMode) -> String {
        switch mode {
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        case .system: return String(localized: "System")
        }
    }

    // MARK: - Sparkline theme picker

    private var sparklineThemePicker: some View {
        ForEach(SparklineTheme.allThemes) { theme in
            Button {
                viewModel.setSparklineTheme(theme.id)
            } label: {
                HStack(spacing: 10) {
                    swatch(for: theme)
                    Text(theme.name)
                        .foregroundStyle(Color.primary)
                    Spacer()
                    if viewModel.sparklineThemeID == theme.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.brandSecondary)
                    } else {
                        Image(systemName: "circle")
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func swatch(for theme: SparklineTheme) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(theme.lineColor)
                .frame(width: 12, height: 12)
            ForEach(0..<theme.gradientColors.count, id: \.self) { index in
                Circle()
                    .fill(theme.gradientColors[index])
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.vertical, 2)
    }
}
