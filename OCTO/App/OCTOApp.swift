import SwiftUI

@main
struct OCTOApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

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
        .sheet(item: $app.whatsNew) { notes in
            WhatsNewView(notes: notes)
        }
        .task {
            #if OCTO_DEMO
            if app.isDemo {
                // Leaves time for sheets and the sidebar to finish animating before the capture.
                try? await Task.sleep(for: .seconds(2.5))
                DemoContent.markReady()
            }
            #endif
        }
    }
}
