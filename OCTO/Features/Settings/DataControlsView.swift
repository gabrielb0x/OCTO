import OCTOCore
import SwiftUI

/// Data settings of the ChatGPT account, read from and saved to the account, and the chats kept on this device.
struct DataControlsView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmDeleteAll = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var settingError: String?

    var body: some View {
        Form {
            Section {
                settingToggle(.trainingAllowed, title: "Improve the model for everyone", systemImage: "sparkles")
                if app.account.settings?.trainingAllowed == true {
                    settingToggle(.voiceTrainingAllowed, title: "Include your audio recordings", systemImage: "waveform")
                    settingToggle(.videoTrainingAllowed, title: "Include your video recordings", systemImage: "video")
                }
            } header: {
                Text(verbatim: "ChatGPT")
            } footer: {
                Text("Lets OpenAI use your chats in ChatGPT to train its models. The switches show what your account has saved and change it right away.")
            }

            Section {
                settingToggle(.codexTrainingAllowed, title: "Improve Codex for everyone", systemImage: "chevron.left.forwardslash.chevron.right")
            } header: {
                Text("Messages written in OCTO")
            } footer: {
                Text("Replies to the messages you write in OCTO come from Codex, with server-side storage turned off. This is Codex's own training setting.")
            }

            if app.account.dataUsagePermitted == false {
                Section {
                    Label("The policy of your account doesn't allow its data to be used for training.", systemImage: "building.2")
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            Section {
                NavigationLink {
                    ArchivedChatsView()
                } label: {
                    Label("Archived chats", systemImage: "archivebox")
                }
                Button(role: .destructive) {
                    confirmDeleteAll = true
                } label: {
                    HStack {
                        DestructiveLabel(title: "Delete all chats", systemImage: "trash")
                        if isDeleting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isDeleting || app.store.summaries.isEmpty)
                .destructiveRow()
            } footer: {
                Text("Your chats come from your ChatGPT account and are kept on this device so they open instantly.")
            }
        }
        .navigationTitle("Data controls")
        .navigationBarTitleDisplayMode(.inline)
        .detachedRefreshable {
            await app.account.refresh()
        }
        .task {
            await app.account.refresh(ifOlderThan: 30)
        }
        .confirmationDialog("Delete all chats?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete all", role: .destructive, action: deleteAll)
        } message: {
            Text("Every chat of your ChatGPT account and of this device will be deleted. This can't be undone.")
        }
        .alert("Couldn't delete your chats", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Couldn't change this setting", isPresented: settingErrorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(settingError ?? "")
        }
    }

    /// A switch showing the value saved in the account; nothing to change until it's known.
    private func settingToggle(_ feature: AccountSettingFeature, title: LocalizedStringKey, systemImage: String) -> some View {
        let value = app.account.settings?[feature]
        let isSaving = app.account.savingSettings.contains(feature)
        return Toggle(isOn: Binding(get: { value ?? false }, set: { change(feature, to: $0) })) {
            HStack(spacing: 10) {
                Label(title, systemImage: systemImage)
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .disabled(value == nil || isSaving)
    }

    private func change(_ feature: AccountSettingFeature, to value: Bool) {
        Task {
            do {
                try await app.account.setSetting(feature, to: value)
                app.toasts.show(value ? String(localized: "Turned on in your ChatGPT account") : String(localized: "Turned off in your ChatGPT account"))
            } catch let error where !error.isCancellation {
                settingError = ChatSession.describe(error)
            } catch {
                // Leaving the page cancels nothing: the account keeps what was sent.
            }
        }
    }

    private func deleteAll() {
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await app.store.deleteAll()
            } catch {
                errorMessage = ChatSession.describe(error)
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var settingErrorIsPresented: Binding<Bool> {
        Binding(get: { settingError != nil }, set: { if !$0 { settingError = nil } })
    }
}

/// Chats archived in the ChatGPT account, which can be put back in the history.
struct ArchivedChatsView: View {
    @Environment(AppModel.self) private var app
    @State private var chats: [RemoteConversationSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var chatToDelete: RemoteConversationSummary?

    var body: some View {
        List {
            if isLoading, chats.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let errorMessage, chats.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
            } else if chats.isEmpty {
                Text("No archived chats.")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Section {
                    ForEach(chats) { chat in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: chat.title.isEmpty ? String(localized: "New chat") : chat.title)
                                .lineLimit(1)
                            if let date = chat.updatedAt {
                                Text(date, format: .dateTime.day().month().year())
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                chatToDelete = chat
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                unarchive(chat)
                            } label: {
                                Label("Unarchive", systemImage: "tray.and.arrow.up")
                            }
                            .tint(Theme.link)
                        }
                        .contextMenu {
                            Button {
                                unarchive(chat)
                            } label: {
                                Label("Unarchive", systemImage: "tray.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                chatToDelete = chat
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } footer: {
                    Text("Swipe a chat to put it back in your history, or to delete it from your ChatGPT account.")
                }
            }
        }
        .navigationTitle("Archived chats")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this archived chat?",
            isPresented: deleteIsPresented,
            titleVisibility: .visible,
            presenting: chatToDelete
        ) { chat in
            Button("Delete", role: .destructive) {
                delete(chat)
            }
        } message: { _ in
            Text("This can't be undone.")
        }
        .task {
            await load()
        }
        .detachedRefreshable {
            await load()
        }
    }

    private func load() async {
        guard let service = app.store.service else {
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            chats = try await service.conversations(offset: 0, limit: 100, archived: true).items
            errorMessage = nil
        } catch let error where !error.isCancellation {
            errorMessage = ChatSession.describe(error)
        } catch {
            // Leaving the screen cancels the request.
        }
    }

    private func unarchive(_ chat: RemoteConversationSummary) {
        guard let service = app.store.service else { return }
        chats.removeAll { $0.id == chat.id }
        Task {
            do {
                try await service.setArchived(false, conversationID: chat.id)
                await app.store.syncWithAccount()
            } catch {
                errorMessage = ChatSession.describe(error)
                await load()
            }
        }
    }

    /// Deletes an archived chat in the ChatGPT account, and on the device when it was downloaded.
    private func delete(_ chat: RemoteConversationSummary) {
        guard let service = app.store.service else { return }
        chats.removeAll { $0.id == chat.id }
        Task {
            do {
                try await service.delete(conversationID: chat.id)
                await app.store.syncWithAccount()
                app.toasts.show(String(localized: "The chat has been deleted"))
            } catch {
                errorMessage = ChatSession.describe(error)
                await load()
            }
        }
    }

    private var deleteIsPresented: Binding<Bool> {
        Binding(get: { chatToDelete != nil }, set: { if !$0 { chatToDelete = nil } })
    }
}
