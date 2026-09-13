import SwiftUI

@main
struct OCTOApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch app.auth.state {
            case .signedOut:
                WelcomeView()
                    .transition(.opacity)
            case .signedIn:
                MainView(app: app)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: app.auth.state)
    }
}
