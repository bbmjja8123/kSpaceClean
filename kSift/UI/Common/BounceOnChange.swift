import SwiftUI

/// Bounces a symbol (or symbol-bearing label) whenever `value` changes.
/// No-op under Reduce Motion and on macOS 13 (`.symbolEffect` is 14+).
struct BounceOnChange: ViewModifier {
    let value: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *), !reduceMotion {
            content.symbolEffect(.bounce, value: value)
        } else {
            content
        }
    }
}
