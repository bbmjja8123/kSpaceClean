// kWise/Features/Cleanup/Views/DangerousConfirmDialog.swift
import SwiftUI

/// Final confirmation gate for cleanup selections containing Dangerous items.
///
/// The confirmation action remains disabled until the user enters the exact,
/// case-sensitive token `DELETE`. The caller owns presentation and dismissal;
/// this view only reports confirmation or cancellation through its closures.
struct DangerousConfirmDialog: View {
    /// Invoked after the user enters the required token and confirms cleanup.
    let onConfirm: () -> Void
    /// Invoked when the user cancels the destructive operation.
    let onCancel: () -> Void

    @State private var inputText = ""

    /// Returns whether the supplied text exactly matches the confirmation token.
    ///
    /// Whitespace and case differences are intentionally rejected so accidental
    /// input cannot unlock the destructive action.
    static func isConfirmationValid(_ input: String) -> Bool {
        input == "DELETE"
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "flame.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.riskDangerous)
                .accessibilityHidden(true)

            Text("危险操作")
                .font(Typography.largeTitle())
                .foregroundStyle(Color.textPrimary)

            Text("这些操作不可逆。请输入 DELETE 以确认。")
                .font(Typography.regularBody())
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            TextField("", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .accessibilityLabel("输入 DELETE 确认")

            HStack(spacing: Spacing.md) {
                Button("取消", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape, modifiers: [])

                Button("确 认", role: .destructive, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.riskDangerous)
                    .disabled(!Self.isConfirmationValid(inputText))
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(Spacing.lg)
        .frame(width: 480)
        .background(Color.bgElevated)
        .accessibilityElement(children: .contain)
    }
}
