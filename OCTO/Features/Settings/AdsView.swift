import OCTOCore
import SwiftUI

/// Ads of the ChatGPT account: how they're chosen, what ChatGPT keeps about them, the trade a free
/// account can make to be rid of them, and the button that deletes the advertising profile.
/// OCTO itself never shows an ad — these are the account's own settings, changed as in ChatGPT.
struct AdsSettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmDelete = false
    @State private var isDeleting = false

    /// The ads trade only means something without a subscription. An account whose plan OCTO
    /// couldn't read is still offered it, rather than having it hidden for nothing.
    private var offersFreeAdsOptOut: Bool {
        ChatGPTPlan.isPaid(app.planType) != true
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No ads in OCTO", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.success)
                    Text("OCTO never shows ads and sends nothing to advertisers: no telemetry, no analytics, no third-party code. The switches below are your ChatGPT account's own, read from it and changed in it.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.vertical, 4)
            }

            Section {
                AccountSettingToggle(feature: .adsPersonalization, title: "Personalized ads", systemImage: "sparkles.rectangle.stack")
                AccountSettingToggle(feature: .adsHistory, title: "Keep an ad history", systemImage: "clock.arrow.circlepath")
            } header: {
                Text("In ChatGPT")
            } footer: {
                Text("Personalized ads are chosen from what you do in ChatGPT. The history is the list of ads you were shown and interacted with. Turning them off doesn't remove what's already been kept — deleting your advertising data does.")
            }

            if offersFreeAdsOptOut {
                Section {
                    AccountSettingToggle(feature: .freeAdsOptOut, title: "No ads, fewer messages", systemImage: "megaphone.slash")
                } header: {
                    Text("Free plan")
                } footer: {
                    Text("Stays on the free plan and turns its ads off, in exchange for fewer messages a day. You can switch it back at any time.")
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    HStack {
                        DestructiveLabel(title: "Delete advertising data", systemImage: "trash")
                        if isDeleting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isDeleting)
                .destructiveRow()
            } footer: {
                Text("Deletes the advertising profile ChatGPT built for your account. This can't be undone, and ChatGPT starts a new one as you keep using it.")
            }
        }
        .navigationTitle("Ads management")
        .navigationBarTitleDisplayMode(.inline)
        .detachedRefreshable {
            await app.account.refresh()
        }
        .task {
            await app.account.refresh(ifOlderThan: 30)
        }
        .confirmationDialog("Delete your advertising data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("The advertising profile ChatGPT keeps for your account will be deleted. This can't be undone.")
        }
    }

    private func delete() {
        guard !isDeleting else { return }
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await app.account.deleteAdsProfile()
                app.toasts.show(String(localized: "Your advertising data has been deleted"))
            } catch {
                app.toasts.show(ChatSession.describe(error), style: .failure)
            }
        }
    }
}
