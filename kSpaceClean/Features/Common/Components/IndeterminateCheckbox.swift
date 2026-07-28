import SwiftUI

struct IndeterminateCheckbox: View {
    let state: CheckState
    var size: CGFloat = RowSize.checkboxSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(state == .off ? Color.clear : Color.brandPrimary)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .stroke(state == .off ? Color.textTertiary : Color.clear, lineWidth: 1.5)
                )
            if state == .mixed {
                Image(systemName: "minus")
                    .font(.system(size: size * 0.66, weight: .bold))
                    .foregroundStyle(.white)
            } else if state == .on {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.66, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .animation(.accessibleDefault(.easeOut(duration: 0.15)), value: state)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var accessibilityLabelText: String {
        switch state {
        case .off: return "未勾选"
        case .on: return "已勾选"
        case .mixed: return "部分勾选"
        case .unchecked: return "未勾选"
        case .checked: return "已勾选"
        }
    }
}

#if DEBUG
struct IndeterminateCheckbox_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            IndeterminateCheckbox(state: .off)
            IndeterminateCheckbox(state: .on)
            IndeterminateCheckbox(state: .mixed)
        }
        .padding()
        .background(Color.bgCanvas)
    }
}
#endif
