import SwiftUI

/// A single row in the process ranking table.
///
/// Displays process name, PID, CPU percentage, memory usage, and network rate.
/// All formatting is performed by `ProcessRowViewModel` — this view only
/// arranges pre-formatted text into columns.
public struct ProcessRowView: View {
    public let viewModel: ProcessRowViewModel

    public init(viewModel: ProcessRowViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 8) {
            Text(viewModel.name)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .help(viewModel.name)
                .font(.body)

            Text("\(viewModel.pid)")
                .frame(width: 50, alignment: .trailing)
                .foregroundStyle(.secondary)
                .font(.caption)

            Text(viewModel.cpuDisplay)
                .frame(width: 50, alignment: .trailing)
                .font(.caption)
                .monospacedDigit()

            Text(viewModel.memoryDisplay)
                .frame(width: 80, alignment: .trailing)
                .font(.caption)
                .monospacedDigit()

            Text(viewModel.networkDisplay)
                .frame(width: 90, alignment: .trailing)
                .font(.caption)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

#Preview("Process row") {
    ProcessRowView(viewModel: ProcessRowViewModel(
        pid: 1234,
        name: "Safari",
        cpuPercent: 12.5,
        memoryBytes: 145_000_000,
        networkBytesPerSecond: 2_300_000
    ))
    .padding(8)
    .frame(width: 500)
}
