import OCTOCore
import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var app
    @Bindable var session: ChatSession
    let onOpenSidebar: () -> Void
    let onNewChat: () -> Void
    let onToggleTemporary: () -> Void
    let onDelete: () -> Void
    let onUpgrade: () -> Void

    @State private var scrollPosition = ScrollPosition(idType: UUID.self, edge: .bottom)
    @State private var isNearBottom = true
    @State private var viewportHeight: CGFloat = 0
    @State private var sentMessageHeight: CGFloat = 0
    @State private var editingMessage: ChatMessage?
    @State private var showVoiceMode = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if !session.messages.isEmpty {
                    messageList
                        .id(session.id)
                } else if session.conversation.isAccountChat {
                    AccountChatPlaceholder(load: session.accountLoad) {
                        Task { await session.loadFromAccount(force: true) }
                    }
                } else {
                    EmptyChatView(isTemporary: session.isTemporary, showsGreeting: app.settings.showsGreeting)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaBar(edge: .bottom) {
                ComposerView(session: session) {
                    showVoiceMode = true
                }
            }
            .overlay(alignment: .bottom) {
                if !isNearBottom, !session.messages.isEmpty {
                    GlassIconButton(systemImage: "arrow.down", label: "Scroll to bottom", size: 38) {
                        withAnimation(.smooth) {
                            scrollPosition.scrollTo(edge: .bottom)
                        }
                    }
                    .padding(.bottom, 12)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: isNearBottom)
            .sheet(item: $editingMessage) { message in
                EditMessageSheet(message: message) { text in
                    session.edit(message.id, text: text)
                }
            }
            .alert("Rename chat", isPresented: $isRenaming) {
                TextField("Title", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    session.rename(renameText)
                }
            }
            .confirmationDialog("Delete this chat?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: onDelete)
            } message: {
                Text("This can't be undone.")
            }
        }
        .fullScreenCover(isPresented: $showVoiceMode) {
            VoiceModeView(session: session)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: session.sentCount) { _, _ in
            app.settings.hapticsEnabled
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: session.completedCount) { _, _ in
            app.settings.hapticsEnabled
        }
        .task(id: session.id) {
            #if OCTO_DEMO
            if app.demoScene == .voice {
                try? await Task.sleep(for: .milliseconds(600))
                showVoiceMode = true
                return
            }
            #endif
            await session.loadFromAccount()
        }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.messageSpacing) {
                ForEach(session.messages) { message in
                    MessageRow(
                        message: message,
                        session: session,
                        isLast: message.id == session.messages.last?.id,
                        showsLocalNote: message.id == session.firstLocalMessageID,
                        onEdit: { editingMessage = message }
                    )
                    .frame(minHeight: roomForReply(below: message), alignment: .topLeading)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        if message.id == session.lastSentMessageID {
                            sentMessageHeight = height
                        }
                    }
                }
            }
            .readableWidth()
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .chatTextStyle(size: app.settings.chatTextSize, font: app.settings.chatFont)
            .environment(\.wrapsCodeLines, app.settings.wrapsCodeLines)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                isNearBottom: geometry.visibleRect.maxY >= geometry.contentSize.height - 140,
                viewportHeight: geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
            )
        } action: { _, metrics in
            isNearBottom = metrics.isNearBottom
            viewportHeight = metrics.viewportHeight
        }
        .onChange(of: session.sentCount) { _, _ in
            guard let messageID = session.lastSentMessageID else { return }
            // The question moves to the top and the reply is written below it. The chat doesn't
            // follow the reply as it grows: scrolling stays in the user's hands.
            Task { @MainActor in
                withAnimation(.smooth(duration: 0.4)) {
                    scrollPosition.scrollTo(id: messageID, anchor: .top)
                }
                // Sending puts the keyboard away, which gives the chat back the height it took.
                // Once it's gone, the question is placed again so the chat really ends at the bottom.
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.smooth(duration: 0.2)) {
                    scrollPosition.scrollTo(id: messageID, anchor: .top)
                }
            }
        }
    }

    /// Minimum height of the reply to the question just sent, so that question can sit at the top of the screen.
    private func roomForReply(below message: ChatMessage) -> CGFloat? {
        guard message.role == .assistant,
              let sentID = session.lastSentMessageID,
              message.id == session.messages.last?.id,
              session.messages.dropLast().last?.id == sentID
        else { return nil }
        let room = viewportHeight - sentMessageHeight - Theme.messageSpacing - 24
        return room > 0 ? room : nil
    }

    // MARK: Toolbar

    /// Free accounts get the upgrade offer in the top bar in place of the model picker.
    private var showsUpgrade: Bool {
        !app.allowsModelChoice && app.showsUpgradeOffer
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onOpenSidebar) {
                Image("SidebarIcon")
            }
            .accessibilityLabel(Text("Open sidebar"))
        }

        // The offer to upgrade sits next to the button that opens the chats, as in the ChatGPT app.
        // The spacer keeps it out of the glass of that button.
        if showsUpgrade {
            ToolbarSpacer(.fixed, placement: .topBarLeading)
            ToolbarItem(placement: .topBarLeading) {
                UpgradePill(action: onUpgrade)
            }
        }

        if app.allowsModelChoice {
            ToolbarItem(placement: .principal) {
                ModelMenu(session: session)
            }
        } else if !showsUpgrade {
            // Without a subscription ChatGPT offers no choice of model, so there's no picker.
            ToolbarItem(placement: .principal) {
                Text(verbatim: "ChatGPT")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityAddTraits(.isHeader)
            }
        }

        if session.isBlank {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onToggleTemporary) {
                    Image(session.isTemporary ? "TemporaryChatOn" : "TemporaryChat")
                }
                .accessibilityLabel(Text("Temporary chat"))
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel(Text("New chat"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                optionsMenu
            }
        }
    }

    private var optionsMenu: some View {
        Menu {
            if !session.isTemporary {
                Button {
                    renameText = session.title
                    isRenaming = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    session.setPinned(!session.conversation.isPinned)
                } label: {
                    Label(
                        session.conversation.isPinned ? LocalizedStringKey("Unpin") : LocalizedStringKey("Pin"),
                        systemImage: session.conversation.isPinned ? "pin.slash" : "pin"
                    )
                }
            }
            ShareLink(item: app.settings.shareableText(session.markdownExport)) {
                Label("Share chat", systemImage: "square.and.arrow.up")
            }
            .disabled(session.isStreaming || session.messages.isEmpty)
            Divider()
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(Text("More options"))
    }
}

private struct ScrollMetrics: Equatable {
    var isNearBottom: Bool
    var viewportHeight: CGFloat
}

/// Title of the chat screen, like "ChatGPT ›" in the official app: model and thinking level.
struct ModelMenu: View {
    @Environment(AppModel.self) private var app
    let session: ChatSession

    var body: some View {
        let current = session.model
        Menu {
            Section("Model") {
                ForEach(app.models) { model in
                    Button {
                        session.selectModel(model)
                    } label: {
                        if model.id == current.id {
                            Label(model.displayName, systemImage: "checkmark")
                        } else {
                            Text(verbatim: model.displayName)
                        }
                        if let summary = model.summary {
                            Text(verbatim: summary)
                        }
                    }
                }
            }

            if current.supportsReasoning {
                Section("Thinking") {
                    ForEach(current.reasoningEfforts) { option in
                        Button {
                            session.selectReasoningEffort(option.effort)
                        } label: {
                            Label(
                                ReasoningEffortLabel.title(option.effort),
                                systemImage: option.effort == session.reasoningEffort ? "checkmark" : ReasoningEffortLabel.systemImage(option.effort)
                            )
                        }
                    }
                }
            }

            Section {
                if current.supportsWebSearch {
                    Toggle(isOn: Binding(get: { session.conversation.webSearchEnabled }, set: { session.setWebSearch($0) })) {
                        Label("Web search", systemImage: "globe")
                    }
                }
                Toggle(isOn: Binding(get: { session.conversation.imageGenerationEnabled }, set: { session.setImageGeneration($0) })) {
                    Label("Create an image", systemImage: "photo")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(verbatim: current.displayName)
                    .font(.headline)
                if let effort = session.reasoningEffort {
                    Text(verbatim: ReasoningEffortLabel.title(effort))
                        .font(.headline.weight(.regular))
                        .foregroundStyle(Theme.secondaryText)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .lineLimit(1)
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel(Text("Choose model"))
    }
}

struct EmptyChatView: View {
    let isTemporary: Bool
    /// The ChatGPT app leaves a new chat empty; Appearance can bring the greeting back.
    var showsGreeting = false

    var body: some View {
        VStack(spacing: 10) {
            if isTemporary {
                Text("Temporary chat")
                    .font(.title2.weight(.semibold))
                Text("This chat won't appear in your history and nothing is saved on this device.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            } else if showsGreeting {
                Text("What can I help with?")
                    .font(.system(size: 27, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }
}

/// Shown while the messages of an account chat download, or when they couldn't be.
struct AccountChatPlaceholder: View {
    let load: ChatSession.AccountLoad
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            switch load {
            case .idle, .loading:
                ProgressView()
                    .controlSize(.large)
                Text("Loading chat…")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            case .loaded:
                Text("This chat has no messages to show.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(Theme.secondaryText)
                Text(verbatim: message)
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                Button(action: onRetry) {
                    Label("Try again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }
}

struct EditMessageSheet: View {
    let message: ChatMessage
    let onSend: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(message: ChatMessage, onSend: @escaping (String) -> Void) {
        self.message = message
        self.onSend = onSend
        _text = State(initialValue: message.text)
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !message.attachments.isEmpty
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 16)
                .navigationTitle("Edit message")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close) {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onSend(text)
                            dismiss()
                        } label: {
                            Image(systemName: "arrow.up")
                                .foregroundStyle(Theme.onProminent)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.prominentFill)
                        .disabled(!canSend)
                        .accessibilityLabel(Text("Send"))
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .onAppear { isFocused = true }
    }
}
