import SwiftUI

extension View {
    /// Placeholder gate applied to Pro-locked rows.
    ///
    /// Task 8 replaces this no-op with the real `.proGate(featureName:
    /// featureIcon:)` modifier backed by `StoreManager`. Kept as a separate
    /// no-arg overload so Task 3 rows compile against a stable surface.
    @ViewBuilder
    func proGate() -> some View { self }
}
