import SwiftUI
import MetricsKit

/// Second onboarding page: let the user pick a menu-bar style and the
/// free-tier metrics they want enabled by default.
///
/// Temperature, fan, battery, and GPU readings are intentionally hidden here —
/// they are Pro features and are surfaced in the Pro intro page.
struct MenuBarCustomizePage: View {
    @ObservedObject var viewModel: OnboardingViewModel
    let onNext: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "Pick your menu-bar style")).font(.title2).bold()
            Picker(String(localized: "Style"), selection: $viewModel.selectedMode) {
                Text(String(localized: "Trend")).tag(MenuBarMode.trend)
                Text(String(localized: "Numeric")).tag(MenuBarMode.numeric)
                Text(String(localized: "Minimal")).tag(MenuBarMode.minimal)
            }
            .pickerStyle(.segmented)

            Text(String(localized: "Show in menu bar")).font(.headline)
            ForEach(MetricKind.allCases.filter { $0 != .temperature && $0 != .fan && $0 != .battery && $0 != .gpu }, id: \.self) { kind in
                Toggle(kind.rawValue.capitalized, isOn: Binding(
                    get: { viewModel.enabledKinds.contains(kind) },
                    set: { isOn in
                        if isOn { viewModel.enabledKinds.insert(kind) }
                        else { viewModel.enabledKinds.remove(kind) }
                    }
                ))
            }
            Spacer()
            HStack {
                Button(String(localized: "Back"), action: onBack)
                Spacer()
                Button(String(localized: "Next"), action: onNext).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }
}