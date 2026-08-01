import SwiftUI

/// Shared layout for a single onboarding page.
///
/// Every page in ``FDAGuideView`` is built from this view so the five screens
/// share one visual rhythm: icon, title, optional subtitle, body copy, then a
/// primary call to action with an optional secondary escape hatch.
///
/// All colours, spacings and animation values come from the shared design
/// system tokens, per `CLAUDE.md` §5.4.
struct FDAGuidePage: View {
    /// SF Symbol shown above the title.
    let icon: String
    /// Page heading.
    let title: String
    /// Optional supporting line under the heading.
    var subtitle: String?
    /// Main body copy. Rendered leading-aligned so bulleted lists line up.
    let message: String
    /// Title of the primary button.
    let ctaTitle: String
    /// Action for the primary button.
    let ctaAction: () -> Void
    /// Title of the optional secondary button.
    var secondaryTitle: String?
    /// Action for the optional secondary button.
    var secondaryAction: (() -> Void)?
    /// Optional status badge shown between the body copy and the buttons.
    var accessory: AnyView?

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer(minLength: AppSpacing.lg)

            Image(systemName: icon)
                .font(AppFont.icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.brandPrimary)
                .accessibilityHidden(true)

            Text(title)
                .font(AppFont.largeTitle)
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)

            if let subtitle {
                Text(subtitle)
                    .font(AppFont.title3)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Text(message)
                .font(AppFont.body)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420, alignment: .leading)

            if let accessory {
                accessory
            }

            Spacer(minLength: AppSpacing.lg)

            VStack(spacing: AppSpacing.sm) {
                Button(ctaTitle, action: ctaAction)
                    .buttonStyle(BrandButtonStyle(isFullWidth: false))
                    .keyboardShortcut(.defaultAction)

                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                        .buttonStyle(.plain)
                        .font(AppFont.callout)
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .padding(AppSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
