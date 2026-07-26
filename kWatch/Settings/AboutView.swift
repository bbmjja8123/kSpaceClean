import SwiftUI
import AppKit
import MetricsKit

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
            Spacer(minLength: 0)

            appIcon
            appName
            versionLabel
            proBadge
            links
            diagnosticsButton
            exportStatus
            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Done") {
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
            .foregroundStyle(Color.accentColor)
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
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    @ViewBuilder
    private var proBadge: some View {
        if viewModel.isPro {
            Text("Pro")
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.18))
                .foregroundStyle(Color.accentColor)
                .clipShape(Capsule())
                .accessibilityLabel("Pro entitlement active")
        } else {
            Text("Free")
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.15))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
                .accessibilityLabel("Free tier")
        }
    }

    private var links: some View {
        VStack(spacing: 6) {
            linkRow(title: "Privacy Policy", action: viewModel.openPrivacyPolicy)
            linkRow(title: "Support", action: viewModel.openSupport)
            linkRow(title: "Open Source Licenses", action: viewModel.openLicenses)
        }
    }

    private func linkRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .foregroundStyle(.secondary)
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
                Text(isExportingDiagnostics ? "Exporting…" : "Export Diagnostics…")
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.regular)
        .disabled(isExportingDiagnostics)
    }

    @ViewBuilder
    private var exportStatus: some View {
        if let url = lastExportURL {
            VStack(spacing: 4) {
                Text("Saved to:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(url.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button("Reveal in Finder") {
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