import OCTOCore
import SwiftUI

struct ChatView: View {
    @Environment(AppModel.self) private var app
    @Bindable var session: ChatSession
    let onOpenSidebar: () -> Void
    let onNewChat: () -> Void
    let onToggleTemporary: () -> Void

    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var isNearBottom = true
    @State private var editingMessage: ChatMessage?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if session.messages.isEmpty {
                    EmptyChatView(isTemporary: session.isTemporary)
                } else {
                    messageList
                        .id(session.id)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaBar(edge: .bottom) {
                ComposerView(session: session)
            }
            .overlay(alignment: .bottom) {
                if !isNearBottom, !session.messages.isEmpty {
                    GlassIconButton(systemImage: "arrow.down", label: "Scroll to bottom", size: 40) {
                        withAnimation(.smooth) {
                            scrollPosition.scrollTo(edge: .bottom)
                        }
                    }
                    .padding(.bottom, 10)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.25), value: isNearBottom)
            .sheet(item: $editingMessage) { message in
                EditMessageSheet(message: message) { text in
                    session.edit(message.id, text: text)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: session.sentCount) { _, _ in
            app.settings.hapticsEnabled
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: session.completedCount) { _, _ in
            app.settings.hapticsEnabled
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
                        onEdit: { editingMessage = message }
                    )
                }
            }
            .readableWidth()
            .padding(.horizontal, Theme.horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .scrollPosition($scrollPosition)
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.visibleRect.maxY >= geometry.contentSize.height - 140
        } action: { _, nearBottom in
            isNearBottom = nearBottom
        }
        .onChange(of: session.messages.last?.text.count) { _, _ in
            if session.isStreaming, isNearBottom {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
        .onChange(of: session.messages.last?.reasoning.count) { _, _ in
            if session.isStreaming, isNearBottom {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
        .onChange(of: session.sentCount) { _, _ in
            withAnimation(.smooth) {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onOpenSidebar) {
                Image(systemName: "line.3.horizontal")
            }
            .accessibilityLabel(Text("Open sidebar"))
        }

        ToolbarItem(placement: .principal) {
            ModelMenu(session: session)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if session.messages.isEmpty {
                Button(action: onToggleTemporary) {
                    Image(systemName: session.isTemporary ? "eye.slash.fill" : "eye.slash")
                }
                .accessibilityLabel(Text("Temporary chat"))
            } else if !session.isStreaming {
                ShareLink(item: session.markdownExport) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(Text("Share chat"))
            }
            Button(action: onNewChat) {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel(Text("New chat"))
        }
    }
}

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

            if current.supportsWebSearch {
                Section {
                    Toggle(isOn: Binding(get: { session.conversation.webSearchEnabled }, set: { session.setWebSearch($0) })) {
                        Label("Web search", systemImage: "globe")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: current.displayName)
                    .font(.headline)
                    .lineLimit(1)
                if let effort = session.reasoningEffort {
                    Text(verbatim: ReasoningEffortLabel.title(effort))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel(Text("Choose model"))
    }
}

struct EmptyChatView: View {
    let isTemporary: Bool

    var body: some View {
        VStack(spacing: 16) {
            if isTemporary {
                Image(systemName: "eye.slash.circle")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Theme.secondaryText)
                Text("Temporary chat")
                    .font(.title2.weight(.semibold))
                Text("This chat won't appear in your history and nothing is saved on this device.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            } else {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
                    .foregroundStyle(.white)
                Text("What can I help with?")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
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
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") {
                            onSend(text)
                            dismiss()
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && message.attachments.isEmpty)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .onAppear { isFocused = true }
    }
}
