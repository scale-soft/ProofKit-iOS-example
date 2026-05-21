import SwiftUI
import ProofKit

@main
struct ProofKit_iOS_exampleApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
