import OCTOCore
import SwiftUI

/// How ChatGPT treats the age of the account (`settings/is_adult`), and why OCTO advises against
/// verifying it.
struct AgeVerificationView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            Section {
                AgeStatusCard(status: app.account.ageStatus, isLoading: app.account.state == .loading)
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(AgeVerificationReason.all) { reason in
                    AgeVerificationReasonRow(reason: reason)
                }
            } header: {
                Text("Our advice: don't verify your age")
            } footer: {
                Text("OCTO never asks for your face or an ID, and never starts a verification.")
            }

            Section {
                Text("If ChatGPT thinks you're under 18, it answers some sensitive topics more carefully and limits a few features. That's the trade-off for keeping your face and your papers to yourself. And if you are under 18, these protections are there for you.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.vertical, 4)
            } header: {
                Text("Without verification")
            }

            Section("Sources") {
                LinkRow(title: "OpenAI: age prediction in ChatGPT", systemImage: "doc.text", url: URL(string: "https://help.openai.com/en/articles/12652064-age-prediction-in-chatgpt")!)
                LinkRow(title: "Proton: ChatGPT for Teens and age verification", systemImage: "doc.text", url: URL(string: "https://proton.me/blog/chatgpt-for-teens")!)
                LinkRow(title: "TechCrunch: 70,000 ID photos stolen after Discord's age checks", systemImage: "doc.text", url: URL(string: "https://techcrunch.com/2025/10/09/discord-suffers-data-breach-impacting-at-least-70000-users/")!)
                LinkRow(title: "TechCrunch: the Tea app leaks 13,000 selfies and IDs", systemImage: "doc.text", url: URL(string: "https://techcrunch.com/2025/07/26/dating-safety-app-tea-breached-exposing-72000-user-images/")!)
            }
        }
        .navigationTitle("Age verification")
        .navigationBarTitleDisplayMode(.inline)
        .detachedRefreshable {
            await app.account.refresh()
        }
        .task {
            await app.account.refresh(ifOlderThan: 60)
        }
    }
}

/// Where the account stands, as ChatGPT reports it.
private struct AgeStatusCard: View {
    let status: AgeStatus?
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 72, height: 72)
                .glassEffect(.regular, in: .circle)
            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var standing: AgeStatus.Standing? {
        status?.standing
    }

    private var symbol: String {
        switch standing {
        case .verifiedAdult?: return "checkmark.seal.fill"
        case .adult?: return "checkmark.seal"
        case .underEighteen?: return "person.crop.circle.badge.exclamationmark"
        case .unknown?, nil: return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch standing {
        case .verifiedAdult?, .adult?: return Theme.success
        case .underEighteen?: return Theme.warning
        case .unknown?, nil: return Theme.secondaryText
        }
    }

    private var title: LocalizedStringKey {
        switch standing {
        case .verifiedAdult?: return "Your age is verified"
        case .adult?: return "ChatGPT treats you as an adult"
        case .underEighteen?: return "ChatGPT treats you as under 18"
        case .unknown?: return "ChatGPT doesn't say how it treats your age"
        case nil: return isLoading ? "Checking your account…" : "Your age status isn't loaded"
        }
    }

    private var detail: LocalizedStringKey {
        switch standing {
        case .verifiedAdult?: return "The verification is already done: there's nothing more to send."
        case .adult?: return "No verification is needed for your account."
        case .underEighteen?: return "Your account has ChatGPT's protections for teens. To lift them, ChatGPT asks you to verify your age with a selfie or an ID."
        case .unknown?: return "Pull down to try again."
        case nil: return "Pull down to load it from your ChatGPT account."
        }
    }
}

private struct AgeVerificationReason: Identifiable {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var id: String { systemImage }

    static var all: [AgeVerificationReason] {
        [
            AgeVerificationReason(
                systemImage: "faceid",
                title: "Your face and your ID go to another company",
                detail: "ChatGPT has the check done by Persona, a verification company. Depending on the country, it asks for a live selfie, a photo of a government ID, or both."
            ),
            AgeVerificationReason(
                systemImage: "exclamationmark.lock",
                title: "Verification data leaks",
                detail: "In October 2025, about 70,000 ID photos sent to Discord to check users' age were stolen from one of its providers. In July 2025, the Tea app leaked 13,000 selfies and IDs it had promised to delete right after checking them."
            ),
            AgeVerificationReason(
                systemImage: "person.text.rectangle",
                title: "Your identity tied to every chat",
                detail: "Once verified, your account is linked to your face, your date of birth and your papers. Your chats, often very personal, no longer belong to an anonymous account."
            ),
            AgeVerificationReason(
                systemImage: "arrow.triangle.2.circlepath",
                title: "A face can't be changed",
                detail: "A leaked password can be replaced. Your face and your identity can't: a leak is for good."
            ),
            AgeVerificationReason(
                systemImage: "hand.raised",
                title: "You have to take their word for it",
                detail: "OpenAI says it doesn't receive the selfie or the ID, and that Persona deletes them within seven days. Nothing lets you check it, and nothing you send can be taken back."
            ),
            AgeVerificationReason(
                systemImage: "eye",
                title: "An age guessed from your habits",
                detail: "ChatGPT estimates your age from the topics you talk about, the hours you use it and how old your account is. Verifying answers that guess with even more personal data."
            ),
            AgeVerificationReason(
                systemImage: "checkmark.circle",
                title: "It's optional",
                detail: "Nothing forces you to verify: without it, you keep using ChatGPT, with its protections for teens."
            ),
        ]
    }
}

private struct AgeVerificationReasonRow: View {
    let reason: AgeVerificationReason

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: reason.systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 28)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(reason.title)
                    .font(.body.weight(.semibold))
                Text(reason.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
