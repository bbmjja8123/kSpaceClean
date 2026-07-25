import SwiftUI

struct AppDetailView: View {
    let app: InstalledApp

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(app.displayName)
                .font(.title)

            Text(app.bundleID)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(app.sizeFormatted)
                .font(.headline)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
