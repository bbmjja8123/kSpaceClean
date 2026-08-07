import SwiftUI
import AppKit
import MetricsKit
import DesignSystem

/// About pane: app version, Pro status, support and policy links, open
/// source licenses, and a diagnostics export action. Rendered inside the
/// Settings window's tab view and as the standalone "About kWatch" window
/// triggered from the menu bar.
struct AboutView: View {
    @ObservedObject var viewModel: SettingsViewModel
    public let onCloseRequested: () -> Void

    @State private var isExportingDiagnostics = false
    @State private var lastExportURL: URL?

    public init(viewModel: SettingsViewModel, onCloseRequested: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onCloseRequested = onCloseRequested
    }

    public var body: some View {
        VStack(spacing: 16) {
            appIcon
            appName
            versionLabel
            proBadge
            links
            diagnosticsButton
            restorePurchasesButton
            exportStatus
            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(String(localized: "Done")) {
                    onCloseRequested()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420, height: 460)
    }

    // MARK: - Subviews

    private var appIcon: some View {
        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
            .resizable()
            .scaledToFit()
            .frame(width: 80, height: 80)
            .foregroundStyle(Color.brandSecondary)
            .accessibilityHidden(true)
    }

    private var appName: some View {
        Text("kWatch")
            .font(.title)
            .fontWeight(.bold)
    }

    private var versionLabel: some View {
        Text("Version \(viewModel.buildNumber)")
            .font(.callout)
            .foregroundStyle(Color.textSecondary)
            .monospacedDigit()
    }

    @ViewBuilder
    private var proBadge: some View {
        if viewModel.isPro {
            Text(String(localized: "Pro"))
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.brandSecondary.opacity(0.18))
                .foregroundStyle(Color.brandSecondary)
                .clipShape(Capsule())
                .accessibilityLabel(String(localized: "Pro entitlement active"))
        } else {
            Text(String(localized: "Free"))
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.textSecondary.opacity(0.15))
                .foregroundStyle(Color.textSecondary)
                .clipShape(Capsule())
                .accessibilityLabel(String(localized: "Free tier"))
        }
    }

    private var links: some View {
        VStack(spacing: 6) {
            linkRow(title: String(localized: "Privacy Policy"), action: viewModel.openPrivacyPolicy)
            linkRow(title: String(localized: "Support"), action: viewModel.openSupport)
            linkRow(title: String(localized: "Open Source Licenses"), action: viewModel.openLicenses)
        }
    }

    private func linkRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .foregroundStyle(Color.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.link)
    }

    private var diagnosticsButton: some View {
        Button {
            Task { await runDiagnosticsExport() }
        } label: {
            HStack {
                if isExportingDiagnostics {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "stethoscope")
                }
                Text(isExportingDiagnostics ? String(localized: "Exporting…") : String(localized: "Export Diagnostics…"))
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.regular)
        .disabled(isExportingDiagnostics)
    }

    @ViewBuilder
    private var restorePurchasesButton: some View {
        Button {
            viewModel.restorePurchases()
        } label: {
            HStack {
                Image(systemName: "arrow.clockwise.circle")
                Text(String(localized: "Restore Purchases"))
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.regular)
        .help(String(localized: "Restore a previous Pro purchase linked to your Apple ID."))
    }

    @ViewBuilder
    private var exportStatus: some View {
        if let url = lastExportURL {
            VStack(spacing: 4) {
                Text(String(localized: "Saved to:"))
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                Text(url.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button(String(localized: "Reveal in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Actions

    private func runDiagnosticsExport() async {
        isExportingDiagnostics = true
        defer { isExportingDiagnostics = false }
        lastExportURL = await viewModel.exportDiagnostics()
    }
}