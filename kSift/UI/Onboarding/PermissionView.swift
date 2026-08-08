//
//  PermissionView.swift
//  kSift
//
//  Non-blocking Full Disk Access status card shown during onboarding.
//  Reflects the live FDAStatus and offers one-tap actions to grant or
//  re-check the permission without forcing the user down that path.
//

import SwiftUI
import DesignSystem

/// Non-blocking permission card: green check when granted, orange call-out
/// with actions when denied. The user can always skip it and continue.
struct PermissionView: View {
    @Binding var fdaStatus: FDAStatus

    var body: some View {
        HStack(spacing: AppSpacing.lg) {
            Image(systemName: iconName)
                .font(AppFont.title2)
                .foregroundColor(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(titleKey)
                    .font(AppFont.title3)
                    .foregroundColor(.textPrimary)
                Text(detailKey)
                    .font(AppFont.callout)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: AppSpacing.md)

            if fdaStatus == .denied {
                Button("Open System Settings") { FDAChecker.openSystemSettings() }
                Button("Re-check") { fdaStatus = FDAChecker.status() }
            }
        }
        .padding(AppSpacing.lg)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .stroke(iconColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var isGranted: Bool {
        fdaStatus == .granted
    }

    private var iconName: String {
        isGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
    }

    private var iconColor: Color {
        isGranted ? .success : .warning
    }

    private var titleKey: LocalizedStringKey {
        isGranted ? "Full Disk Access granted" : "Full Disk Access required"
    }

    private var detailKey: LocalizedStringKey {
        isGranted
            ? "kSift can scan protected folders like Desktop, Documents, and Downloads."
            : "kSift needs Full Disk Access to scan protected folders like Desktop, Documents, and Downloads."
    }
}
