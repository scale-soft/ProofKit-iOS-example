import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            SetupView()
                .tabItem { Label("Setup", systemImage: "gear") }

            CameraTabView()
                .tabItem { Label("Camera", systemImage: "camera.fill") }

            CapturesView()
                .tabItem { Label("Captures", systemImage: "photo.on.rectangle.angled") }
                .badge(appState.captures.isEmpty ? 0 : appState.captures.count)

            VerifyView()
                .tabItem { Label("Verify", systemImage: "checkmark.shield.fill") }
        }
    }
}
