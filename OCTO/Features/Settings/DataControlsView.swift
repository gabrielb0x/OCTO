import OCTOCore
import SwiftUI

/// Data settings of the ChatGPT account and the chats kept on this device.
struct DataControlsView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmDeleteAll = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    trainingValue
                } label: {
                    Label("Improve the model for everyone", systemImage: "sparkles")
                }
            } footer: {
                Text("Managed in ChatGPT. The messages you write in OCTO are sent with server-side storage turned off.")
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
                        Label("Delete all chats", systemImage: "trash")
                        if isDeleting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isDeleting || app.store.summaries.isEmpty)
            } footer: {
                Text("Your chats come from your ChatGPT account and are kept on this device so they open instantly.")
            }
        }
        .navigationTitle("Data controls")
        .navigationBarTitleDisplayMode(.inline)
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
    }

    private var trainingValue: Text {
        switch app.account.trainingAllowed ?? app.account.settings?.trainingAllowed {
        case true?: return Text("On")
        case false?: return Text("Off")
        case nil: return Text(verbatim: "–")
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
}

/// Chats archived in the ChatGPT account, which can be put back in the history.
struct ArchivedChatsView: View {
    @Environment(AppModel.self) private var app
    @State private var chats: [RemoteConversationSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

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
                        }
                    }
                } footer: {
                    Text("Swipe a chat to put it back in your history.")
                }
            }
        }
        .navigationTitle("Archived chats")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .refreshable {
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
        } catch {
            errorMessage = ChatSession.describe(error)
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
}
