import OCTOCore
import SwiftUI

@main
struct OCTOApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        let removesTrackers = app.settings.removesLinkTrackers

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
        .preferredColorScheme(app.settings.theme.colorScheme)
        // Links of replies and sources open without their tracking parameters.
        .environment(\.openURL, OpenURLAction { url in
            .systemAction(removesTrackers ? LinkCleaner.clean(url) : url)
        })
        .sheet(item: $app.whatsNew) { notes in
            WhatsNewView(notes: notes)
        }
        .sheet(item: $app.updatePrompt) { release in
            UpdateView(release: release)
        }
        .onAppear {
            app.overlays.install(app: app)
            app.settings.theme.apply()
        }
        .onChange(of: app.settings.theme) { _, theme in
            // Also reverts to the system appearance, which preferredColorScheme alone doesn't do.
            theme.apply()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            app.protection.scenePhaseChanged(to: phase)
            if phase == .active {
                Task {
                    await app.notifications.refreshAuthorization()
                    await app.checkForUpdatesIfDue()
                }
            }
        }
        .onChange(of: app.protection.showsCover, initial: true) { _, isVisible in
            app.overlays.install(app: app)
            app.overlays.setCoverVisible(isVisible)
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
