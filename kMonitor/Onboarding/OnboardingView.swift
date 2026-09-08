import SwiftUI
import MetricsKit

/// SwiftUI container for the four-step onboarding flow.
///
/// `OnboardingView` is a thin coordinator: it owns no state itself but
/// forwards navigation actions to `OnboardingViewModel` and switches the
/// rendered page based on `viewModel.page`. The progress bar reflects the
/// current step out of the total page count.
public struct OnboardingView: View {
    @ObservedObject public var viewModel: OnboardingViewModel
    public let onCloseRequested: () -> Void

    public init(viewModel: OnboardingViewModel, onCloseRequested: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onCloseRequested = onCloseRequested
    }

    public var body: some View {
        VStack {
            progressBar
            Group {
                switch viewModel.page {
                case .welcome:
                    WelcomePage(onNext: viewModel.next)
                case .customize:
                    MenuBarCustomizePage(
                        viewModel: viewModel,
                        onNext: viewModel.next,
                        onBack: viewModel.back
                    )
                case .proIntro:
                    ProIntroPage(onSkip: viewModel.skip, onContinue: viewModel.next)
                case .complete:
                    CompletePage(onOpenMenuBar: {
                        viewModel.complete()
                        onCloseRequested()
                    })
                }
            }
            .frame(width: 480, height: 360)
        }
        .frame(width: 520, height: 420)
    }

    private var progressBar: some View {
        let total = OnboardingViewModel.Page.allCases.count
        let progress = Double(viewModel.page.rawValue + 1) / Double(total)
        return ProgressView(value: progress)
            .progressViewStyle(.linear)
            .padding(.horizontal, 24)
            .padding(.top, 16)
    }
}