import SwiftUI
import MetricsKit
import DesignSystem

// MARK: - Color resolution

extension CardColor {
    /// The concrete `Color` the view layer should render for this token.
    public var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .red: return .red
        case .yellow: return .yellow
        case .gray: return .gray
        }
    }
}

// MARK: - Metric card view

/// A single dashboard metric card.
///
/// The card displays an icon, title, formatted value, and a contextual subtitle.
/// Locked cards (Pro-gated metrics the user has not purchased) show a lock icon
/// and an "Upgrade" prompt. Unavailable cards show a question-mark icon with
/// the capability-reason subtitle.
public struct MetricCardView: View {
    public let viewModel: MetricCardViewModel
    public let onOpenPaywall: (() -> Void)?

    public init(viewModel: MetricCardViewModel, onOpenPaywall: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onOpenPaywall = onOpenPaywall
    }

    public var body: some View {
        VStack(spacing: 8) {
            header
            valueArea
            subtitleView
            if viewModel.isLocked {
                upgradeButton
            }
        }
        .padding(12)
        .background(background)
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.icon)
                .font(.title3)
                .foregroundStyle(viewModel.cardColor.color)
                .frame(width: 24)

            Text(viewModel.title)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    private var valueArea: some View {
        HStack {
            Text(viewModel.displayValue)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(viewModel.cardColor.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 0)
        }
    }

    private var subtitleView: some View {
        HStack {
            Text(viewModel.subtitle)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2, reservesSpace: true)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var upgradeButton: some View {
        Button {
            onOpenPaywall?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                Text(String(localized: "Upgrade to Pro"))
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.brandSecondary)
            )
        }
        .buttonStyle(.plain)
        .help(viewModel.lockDescription)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.bgPrimary)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(viewModel.cardColor.color.opacity(0.3), lineWidth: 1)
            }
    }
}

// MARK: - Preview

struct MetricCardView_Free_Previews: PreviewProvider {
    static var previews: some View {
        let vm = MetricCardViewModel(
            kind: .cpu,
            value: .percentage(67),
            availability: .available,
            isPro: false
        )
        MetricCardView(viewModel: vm) { print("Upgrade tapped") }
            .frame(width: 200)
            .padding()
    }
}

struct MetricCardView_Locked_Previews: PreviewProvider {
    static var previews: some View {
        let vm = MetricCardViewModel(
            kind: .temperature,
            value: .degreesCelsius(72),
            availability: .available,
            isPro: false
        )
        MetricCardView(viewModel: vm) { print("Upgrade tapped") }
            .frame(width: 200)
            .padding()
    }
}

struct MetricCardView_Unavailable_Previews: PreviewProvider {
    static var previews: some View {
        let vm = MetricCardViewModel(
            kind: .fan,
            value: .unavailable(.unsupported("SMC not found")),
            availability: .unsupported(reason: "SMC not found"),
            isPro: true
        )
        MetricCardView(viewModel: vm)
            .frame(width: 200)
            .padding()
    }
}
