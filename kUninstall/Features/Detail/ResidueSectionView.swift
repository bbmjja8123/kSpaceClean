import SwiftUI

struct ResidueSectionView: View {
    let residues: [ResidueFile]
    @Binding var selectedResidues: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("残留文件 (\(residues.count) 项)")
                .font(.headline)

            ForEach(residues) { residue in
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { selectedResidues.contains(residue.id) },
                        set: { if $0 { selectedResidues.insert(residue.id) } else { selectedResidues.remove(residue.id) } }
                    ))
                    .toggleStyle(.checkbox)
                    .disabled(residue.isProtected)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(residue.url.lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                        Text(residue.description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    confidenceBadge(residue.confidence)

                    Text(residue.sizeFormatted)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder private func confidenceBadge(_ confidence: Double) -> some View {
        if confidence >= 0.95 {
            Text("确定")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.green)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.green.opacity(0.1))
                .cornerRadius(3)
        } else if confidence >= 0.8 {
            Text("可能")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.orange)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(3)
        } else {
            Text("低")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(3)
        }
    }
}
