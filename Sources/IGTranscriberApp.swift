import SwiftUI

@main
struct IGTranscriberApp: App {
    @StateObject private var model = TranscriberViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 560)
        }
        .windowResizability(.contentMinSize)
    }
}
