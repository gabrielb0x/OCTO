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

struct AgeVerificationView: View {
    var body: some View {
        ChatGPTOnlyPage(
            title: "Age verification",
            systemImage: "checkmark.shield",
            summary: "ChatGPT can ask you to confirm your age for some content and features.",
            details: "Age verification is done by OpenAI in ChatGPT. OCTO never asks for an ID and doesn't receive any verification data."
        )
    }
}

struct ParentalControlsView: View {
    var body: some View {
        ChatGPTOnlyPage(
            title: "Parental controls",
            systemImage: "figure.and.child.holdinghands",
            summary: "Parents can link their account to a teen's account to adjust how ChatGPT works for them.",
            details: "Parental controls are set up and managed in ChatGPT. OCTO doesn't change them."
        )
    }
}

struct RemoteControlView: View {
    var body: some View {
        ChatGPTOnlyPage(
            title: "Remote control",
            systemImage: "display",
            summary: "Remote control lets the ChatGPT apps work with your other devices.",
            details: "It's only available in the official ChatGPT apps. OCTO doesn't connect to your other devices."
        )
    }
}

struct AdsSettingsView: View {
    var body: some View {
        ChatGPTOnlyPage(
            title: "Ads management",
            systemImage: "megaphone",
            summary: "OCTO shows no ads and doesn't track you.",
            details: "Ads and their personalization are managed with your ChatGPT account in ChatGPT. OCTO sends nothing to advertisers: no telemetry, no analytics, no third-party SDK."
        )
    }
}
