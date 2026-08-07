import SwiftUI

// MARK: - Loading Overlay Modifier

/// A view modifier that overlays a loading indicator on top of content.
public struct LoadingOverlayModifier: ViewModifier {
    let isLoading: Bool
    let title: String
    let progress: Double?

    public init(isLoading: Bool, title: String = "Loading…", progress: Double? = nil) {
        self.isLoading = isLoading
        self.title = title
        self.progress = progress
    }

    public func body(content: Content) -> some View {
        if isLoading {
            content
                .overlay {
                    ZStack {
                        Color.black.opacity(0.4)
                        VStack(spacing: 12) {
                            if let progress {
                                ProgressView(value: progress)
                            } else {
                                ProgressView()
                            }
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.regularMaterial)
                        )
                    }
                }
        } else {
            content
        }
    }
}

// MARK: - Empty State Modifier

/// A view modifier that swaps content for an empty-state placeholder when `isEmpty` is true.
public struct EmptyStateModifier: ViewModifier {
    let isEmpty: Bool
    let iconName: String
    let title: String
    let subtitle: String
    let actionLabel: String
    let action: (() -> Void)?

    public init(
        isEmpty: Bool,
        iconName: String,
        title: String,
        subtitle: String,
        actionLabel: String = "Retry",
        action: (() -> Void)? = nil
    ) {
        self.isEmpty = isEmpty
        self.iconName = iconName
        self.title = title
        self.subtitle = subtitle
        self.actionLabel = actionLabel
        self.action = action
    }

    public func body(content: Content) -> some View {
        if isEmpty {
            VStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let action {
                    Button(actionLabel, action: action)
                        .buttonStyle(.bordered)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content
        }
    }
}

// MARK: - Error State Modifier

/// A view modifier that swaps content for an error placeholder when `message` is non-nil.
public struct ErrorStateModifier<Retry: View>: ViewModifier {
    let message: String?
    let retryAction: Retry?

    public init(message: String?, retryAction: Retry?) {
        self.message = message
        self.retryAction = retryAction
    }

    public func body(content: Content) -> some View {
        if let message {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                if let retryAction {
                    retryAction
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content
        }
    }
}

// MARK: - View extensions

public extension View {
    /// Overlay a loading indicator while `isLoading` is true.
    func loadingOverlay(
        isLoading: Bool,
        title: String = "Loading…",
        progress: Double? = nil
    ) -> some View {
        modifier(LoadingOverlayModifier(isLoading: isLoading, title: title, progress: progress))
    }

    /// Show an empty-state placeholder when `isEmpty` is true.
    func emptyState(
        isEmpty: Bool,
        iconName: String,
        title: String,
        subtitle: String,
        actionLabel: String = "Retry",
        action: (() -> Void)? = nil
    ) -> some View {
        modifier(
            EmptyStateModifier(
                isEmpty: isEmpty,
                iconName: iconName,
                title: title,
                subtitle: subtitle,
                actionLabel: actionLabel,
                action: action
            )
        )
    }

    /// Show an error placeholder with a custom retry view when `message` is non-nil.
    func errorState<Retry: View>(message: String?, retryAction: () -> Retry) -> some View {
        modifier(ErrorStateModifier(message: message, retryAction: retryAction()))
    }

    /// Show an error placeholder when `message` is non-nil, with no retry button.
    func errorState(message: String?) -> some View {
        modifier(ErrorStateModifier(message: message, retryAction: nil as EmptyView?))
    }
}
