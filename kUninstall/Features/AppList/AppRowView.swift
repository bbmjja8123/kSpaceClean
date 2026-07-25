import SwiftUI

struct AppRowView: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.displayName)
                        .font(.system(size: 14, weight: .medium))
                    if app.isProtected {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
                Text(app.bundleID)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(app.sizeFormatted)
                    .font(.system(size: 12, weight: .medium))
                sourceBadge
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    @ViewBuilder private var sourceBadge: some View {
        switch app.source {
        case .system:
            Label("系统", systemImage: "gearshape")
                .font(.system(size: 10))
                .foregroundColor(.red)
        case .appleBuiltIn:
            Label("Apple", systemImage: "applelogo")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        case .mas:
            Text("App Store")
                .font(.system(size: 10))
                .foregroundColor(.blue)
        case .userInstalled:
            EmptyView()
        case .unknown:
            EmptyView()
        }
    }
}
