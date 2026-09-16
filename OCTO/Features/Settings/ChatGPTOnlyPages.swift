import SwiftUI

// Settings of ChatGPT that only the official apps can use. Each page says what the setting does
// and opens ChatGPT, instead of pretending OCTO can change it.

struct PluginsView: View {
    var body: some View {
        ChatGPTOnlyPage(
            title: "Plugins",
            systemImage: "at",
            summary: "Plugins connect ChatGPT to other apps and services, and you call them with @ in a chat.",
            details: "Plugins run inside ChatGPT. Replies in OCTO come from the Codex backend of your plan, which can search the web but can't use the plugins of your account. Add or remove plugins in ChatGPT."
        )
    }
}

struct RemoteControlView: View {
    var body: some View {
        ChatGPTOnlyPage(
            title: "Remote control",
            systemImage: "tv",
            summary: "Remote control lets the ChatGPT apps work with your other devices.",
            details: "It's only available in the official ChatGPT apps. OCTO doesn't connect to your other devices."
        )
    }
}
