import SwiftUI

@main
struct kSpaceCleanApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("kSpaceClean")
            .frame(width: 400, height: 300)
    }
}
