import SwiftUI
import DesignSystem

/// P1-1 multi-dim filter chips: log-stepped size range slider and date-range
/// pickers. Collapsible under the FilterBarView so the default result page
/// stays visually quiet; expanding it shows the controls together with a
/// "Reset" affordance.
struct FilterChipsView: View {
    @Binding var minSize: Int64
    @Binding var maxSize: Int64
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?
    let onReset: () -> Void

    /// Log-spaced size stops in bytes. Indexed by the slider position so
    /// the user gets usable resolution across the 1 KB → 10 GB span
    /// (a linear slider would be unusable at the low end).
    private static let sizeSteps: [Int64] = [
        0,                       // "Any" (no lower bound)
        1_024,                   // 1 KB
        10_240,                  // 10 KB
        102_400,                 // 100 KB
        1_048_576,               // 1 MB
        10_485_760,              // 10 MB
        104_857_600,             // 100 MB
        1_073_741_824,           // 1 GB
        10_737_418_240,          // 10 GB
        Int64.max,               // "Any" (no upper bound)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sizeRangeRow
            Divider()
            dateRangeRow
            if hasAnyFilter {
                Button(action: onReset) {
                    Label(
                        NSLocalizedString("Reset filters", comment: "Reset multi-dim filters"),
                        systemImage: "arrow.counterclockwise"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(.top, AppSpacing.xs)
            }
        }
        .padding(AppSpacing.md)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        .padding(.horizontal, 16)
        .padding(.bottom, AppSpacing.xs)
    }

    // MARK: - Size range

    private var sizeRangeRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(NSLocalizedString("Size range", comment: "Size range filter heading"))
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(formatBytes(minSize)) – \(formatBytes(maxSize))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: AppSpacing.md) {
                sizeStepperColumn(
                    title: NSLocalizedString("Min", comment: "Minimum size label"),
                    value: $minSize,
                    direction: .lower
                )
                sizeStepperColumn(
                    title: NSLocalizedString("Max", comment: "Maximum size label"),
                    value: $maxSize,
                    direction: .upper
                )
            }
        }
    }

    private enum StepperDirection { case lower, upper }

    private func sizeStepperColumn(
        title: String,
        value: Binding<Int64>,
        direction: StepperDirection
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: AppSpacing.xs) {
                Button {
                    stepValue(value: value, direction: direction, by: -1)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                Text(formatBytes(value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 64, alignment: .leading)
                Button {
                    stepValue(value: value, direction: direction, by: 1)
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Advances the bound size value to the next/previous step in
    /// `sizeSteps`. For the lower bound we never let the value exceed
    /// `maxSize - 1 step`; for the upper bound we never let it drop below
    /// `minSize + 1 step`. This keeps the two sliders consistent.
    private func stepValue(
        value: Binding<Int64>,
        direction: StepperDirection,
        by delta: Int
    ) {
        let steps = Self.sizeSteps
        let currentIndex = nearestStepIndex(for: value.wrappedValue, in: steps)
        var newIndex = max(0, min(steps.count - 1, currentIndex + delta))
        // Constrain relative to the other bound so min <= max always.
        switch direction {
        case .lower:
            let maxIndex = nearestStepIndex(for: maxSize, in: steps)
            newIndex = min(newIndex, max(maxIndex - 1, 0))
            if newIndex == 0 { value.wrappedValue = 0; return }
        case .upper:
            let minIndex = nearestStepIndex(for: minSize, in: steps)
            // For the upper knob, index 0 means "any size" (Int64.max).
            newIndex = max(newIndex, minIndex + 1)
            if newIndex == steps.count - 1 { value.wrappedValue = .max; return }
        }
        value.wrappedValue = steps[newIndex]
    }

    private func nearestStepIndex(for value: Int64, in steps: [Int64]) -> Int {
        if value <= 0 { return 0 }
        if value >= .max { return steps.count - 1 }
        var bestIndex = 0
        var bestDiff = Int64.max
        for (i, step) in steps.enumerated() {
            let diff = abs(step - value)
            if diff < bestDiff {
                bestDiff = diff
                bestIndex = i
            }
        }
        return bestIndex
    }

    // MARK: - Date range

    private var dateRangeRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(NSLocalizedString("Date range", comment: "Date range filter heading"))
                .font(.caption.weight(.semibold))
            HStack(spacing: AppSpacing.md) {
                datePickerColumn(
                    title: NSLocalizedString("From", comment: "Date-range from label"),
                    value: $dateFrom
                )
                datePickerColumn(
                    title: NSLocalizedString("To", comment: "Date-range to label"),
                    value: $dateTo
                )
            }
        }
    }

    private func datePickerColumn(
        title: String,
        value: Binding<Date?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: AppSpacing.xs) {
                if value.wrappedValue == nil {
                    Button {
                        value.wrappedValue = defaultDate()
                    } label: {
                        Text(NSLocalizedString("Any date", comment: "Clear date bound"))
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                } else {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { value.wrappedValue ?? defaultDate() },
                            set: { value.wrappedValue = $0 }
                        ),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    Button {
                        value.wrappedValue = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(NSLocalizedString("Clear date", comment: "Clear date bound tooltip"))
                }
            }
        }
    }

    /// Default placeholder for newly-toggled-on date pickers: one year ago
    /// keeps the new bound well outside the typical scan window so it
    /// doesn't accidentally hide everything.
    private func defaultDate() -> Date {
        Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    }

    // MARK: - Helpers

    private var hasAnyFilter: Bool {
        minSize > 0 || maxSize < Int64.max || dateFrom != nil || dateTo != nil
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return NSLocalizedString("Any size", comment: "No size bound") }
        if bytes >= Int64.max { return NSLocalizedString("Any size", comment: "No size bound") }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}