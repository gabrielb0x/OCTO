import OCTOCore
import SwiftUI
import UIKit

struct MessageRow: View {
    @Environment(AppModel.self) private var app
    let message: ChatMessage
    let session: ChatSession
    let isLast: Bool
    /// True for the first message written in OCTO after the account copy of a chat.
    let showsLocalNote: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(spacing: Theme.messageSpacing) {
            if showsLocalNote {
                LocalMessagesNote()
            }
            VStack(spacing: 6) {
                switch message.role {
                case .user:
                    UserMessageView(message: message, canEdit: session.canModify(message), onEdit: onEdit)
                case .assistant:
                    AssistantMessageView(message: message, session: session, isLast: isLast)
                }
                if app.developer.isEnabled, app.developer.showsMessageDetails {
                    MessageDetails(message: message)
                }
            }
        }
    }
}

/// Marks where the messages written in OCTO start in a chat from the ChatGPT account.
struct LocalMessagesNote: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone")
            Text("The messages below are only on this device")
        }
        .font(.footnote)
        .foregroundStyle(Theme.tertiaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Technical details under a message, shown by developer mode.
struct MessageDetails: View {
    let message: ChatMessage

    var body: some View {
        let alignment: HorizontalAlignment = message.role == .user ? .trailing : .leading
        VStack(alignment: alignment, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(Theme.tertiaryText)
        .multilineTextAlignment(message.role == .user ? .trailing : .leading)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var lines: [String] {
        var lines = ["\(message.role.rawValue) · \(message.id.uuidString.prefix(8)) · \(message.status.rawValue) · \(message.createdAt.formatted(date: .abbreviated, time: .standard))"]
        lines.append(message.remoteID.map { "account \($0)" } ?? "written in OCTO")
        if let modelID = message.modelID {
            lines.append("model \(modelID)")
        }
        if let usage = message.usage {
            lines.append("tokens in \(usage.inputTokens) · cached \(usage.cachedInputTokens) · out \(usage.outputTokens) · reasoning \(usage.reasoningTokens)")
        }
        if let duration = message.reasoningDuration {
            lines.append(String(format: "thought %.1f s · %ld reasoning characters", duration, message.reasoning.count))
        }
        if !message.searchQueries.isEmpty {
            lines.append("searched \(message.searchQueries.joined(separator: " | "))")
        }
        if !message.citations.isEmpty || !message.attachments.isEmpty {
            lines.append("\(message.citations.count) sources · \(message.attachments.count) attachments")
        }
        lines.append("\(message.text.count) characters")
        if let error = message.errorMessage {
            lines.append("error \(error)")
        }
        return lines
    }
}

struct UserMessageView: View {
    @Environment(AppModel.self) private var app
    let message: ChatMessage
    let canEdit: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if !message.attachments.isEmpty {
                AttachmentGallery(attachments: message.attachments)
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(Theme.primaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(app.settings.accentStyle.bubble, in: .rect(cornerRadius: 22))
                    .contextMenu {
                        Button {
                            Clipboard.copy(message.text, settings: app.settings)
                        } label: {
                            Label("Copy", systemImage: "square.on.square")
                        }
                        if canEdit {
                            Button(action: onEdit) {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 56)
    }
}

struct AttachmentGallery: View {
    @Environment(AppModel.self) private var app
    let attachments: [MessageAttachment]
    var alignment: HorizontalAlignment = .trailing

    var body: some View {
        let imageSide: CGFloat = attachments.count == 1 ? 200 : 116
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    switch attachment.kind {
                    case .image:
                        imageTile(attachment, side: attachment.isStoredOnDevice ? imageSide : 116)
                    case .text:
                        FileChip(name: attachment.displayName ?? "file", byteCount: attachment.byteCount > 0 ? attachment.byteCount : nil)
                    }
                }
            }
        }
        .defaultScrollAnchor(alignment == .trailing ? UnitPoint.trailing : UnitPoint.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func imageTile(_ attachment: MessageAttachment, side: CGFloat) -> some View {
        Group {
            if attachment.isStoredOnDevice, let image = AttachmentThumbnails.image(for: attachment, files: app.store.files) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                // Images of account chats stay in the account.
                ZStack {
                    Theme.surfaceElevated
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel(Text("Image"))
    }
}

struct FileChip: View {
    let name: String
    let byteCount: Int?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .font(.title3)
                .foregroundStyle(Theme.link)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                if let byteCount {
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
    }
}

struct AssistantMessageView: View {
    let message: ChatMessage
    let session: ChatSession
    let isLast: Bool

    var body: some View {
        AssistantMessageContent(
            message: message,
            live: session.live?.messageID == message.id ? session.live : nil,
            session: session,
            isLast: isLast
        )
    }
}

/// A reply, either stored or still being written (`live`), whose text is then read from the live reply.
private struct AssistantMessageContent: View {
    @Environment(AppModel.self) private var app
    let message: ChatMessage
    let live: LiveReply?
    let session: ChatSession
    let isLast: Bool
    @State private var copied = false

    private var isActive: Bool { live != nil || message.status == .streaming }
    private var activity: ChatSession.Activity { isActive ? session.activity : .idle }
    private var text: String { live?.text ?? message.text }
    private var reasoning: String { live?.reasoning ?? message.reasoning }
    private var reasoningDuration: TimeInterval? { live?.reasoningDuration ?? message.reasoningDuration }
    private var searchQueries: [String] { live?.searchQueries ?? message.searchQueries }
    private var citations: [Citation] { live?.citations ?? message.citations }
    private var showsRawMarkdown: Bool { app.developer.isEnabled && app.developer.showsRawMarkdown }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if activity == .thinking || !reasoning.isEmpty || reasoningDuration != nil {
                ReasoningView(
                    reasoning: reasoning,
                    duration: reasoningDuration,
                    isThinking: activity == .thinking,
                    canExpand: app.settings.showReasoning && !reasoning.isEmpty
                )
            }

            if activity == .searching || !searchQueries.isEmpty {
                SearchStatusView(queries: searchQueries, isSearching: activity == .searching)
            }

            if activity == .drawing {
                ImageStatusView()
            }

            if !message.attachments.isEmpty {
                AttachmentGallery(attachments: message.attachments, alignment: .leading)
            }

            if text.isEmpty {
                if activity == .waiting || activity == .writing {
                    PulsingDot()
                        .padding(.vertical, 4)
                }
            } else if showsRawMarkdown {
                Text(verbatim: text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            } else if let live {
                // Bold and code left open at the end are styled right away.
                MarkdownView(text: MarkdownStreaming.closingOpenInlineMarkers(text))
                    .environment(\.streamingReveal, live.reveal)
            } else {
                MarkdownView(text: text)
                    .textSelection(.enabled)
            }

            if !citations.isEmpty, !isActive {
                SourcesButton(citations: citations)
            }

            switch message.status {
            case .failed:
                ErrorCard(
                    message: message.errorMessage ?? String(localized: "Something went wrong."),
                    needsSignIn: isLast && session.needsSignIn,
                    onRetry: isLast ? { session.retry() } : nil,
                    onSignIn: { Task { await app.signOut() } }
                )
            case .cancelled:
                Label("Stopped", systemImage: "stop.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiaryText)
            case .complete, .streaming:
                EmptyView()
            }

            if !isActive, !message.text.isEmpty {
                actionBar
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionBar: some View {
        HStack(spacing: 2) {
            actionButton(copied ? "checkmark" : "square.on.square", label: "Copy") {
                Clipboard.copy(message.text, settings: app.settings)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            actionButton(app.speech.speakingMessageID == message.id ? "stop.circle" : "speaker.wave.2", label: "Read aloud") {
                app.speech.toggle(messageID: message.id, markdown: message.text, rate: app.settings.speechRate, voiceIdentifier: app.settings.voiceIdentifier)
            }
            ShareLink(item: app.settings.shareableText(message.text)) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Share"))
            if isLast, message.remoteID == nil {
                regenerateMenu
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(Theme.secondaryText)
        .buttonStyle(.plain)
        .padding(.leading, -8)
        .sensoryFeedback(.success, trigger: copied) { _, isCopied in
            isCopied && app.settings.hapticsEnabled
        }
    }

    /// Tap to try again, press and hold to pick another model, like ChatGPT.
    private var regenerateMenu: some View {
        Menu {
            if app.allowsModelChoice, let usedModelTitle {
                Text(verbatim: usedModelTitle)
            }
            Button {
                session.regenerate(message.id)
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
            }
            if app.allowsModelChoice {
                Menu {
                    ForEach(app.availableModels) { model in
                        Button(model.displayName) {
                            session.regenerate(message.id, using: model)
                        }
                    }
                } label: {
                    Label("Change model", systemImage: "cpu")
                }
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        } primaryAction: {
            session.regenerate(message.id)
        }
        .disabled(session.isStreaming)
        .accessibilityLabel(Text("Regenerate"))
    }

    private var usedModelTitle: String? {
        guard let modelID = message.modelID else { return nil }
        let name = app.models.first { $0.id == modelID }?.displayName ?? modelID
        return String(localized: "Used \(name)")
    }

    private func actionButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(label))
    }
}

struct ReasoningView: View {
    let reasoning: String
    let duration: TimeInterval?
    let isThinking: Bool
    let canExpand: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                guard canExpand else { return }
                withAnimation(.smooth(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    if isThinking {
                        Text(verbatim: currentStep.map { String(localized: "Thinking: \($0)") } ?? String(localized: "Thinking"))
                            .lineLimit(1)
                            .shimmering()
                    } else {
                        Text(verbatim: durationTitle)
                    }
                    if canExpand {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, canExpand {
                HStack(alignment: .top, spacing: 12) {
                    Capsule()
                        .fill(Theme.separator)
                        .frame(width: 2)
                    MarkdownView(text: reasoning)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
            }
        }
    }

    /// Reasoning summaries usually start each step with a bold title.
    private var currentStep: String? {
        guard let match = reasoning.matches(of: #/\*\*(.+?)\*\*/#).last else { return nil }
        let step = String(match.output.1).trimmingCharacters(in: .whitespaces)
        return step.isEmpty ? nil : step
    }

    private var durationTitle: String {
        guard let duration, duration >= 1 else {
            return String(localized: "Thought for a moment")
        }
        let seconds = Int(duration.rounded())
        if seconds < 60 {
            return String(localized: "Thought for \(seconds) s")
        }
        return String(localized: "Thought for \(seconds / 60) min")
    }
}

struct SearchStatusView: View {
    let queries: [String]
    let isSearching: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .symbolEffect(.pulse, isActive: isSearching)
            if isSearching {
                Text(verbatim: String(localized: "Searching the web"))
                    .shimmering()
            } else if let query = queries.last {
                Text(verbatim: String(localized: "Searched for “\(query)”"))
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Theme.secondaryText)
        .lineLimit(1)
    }
}

/// Shown while ChatGPT draws an image, until it arrives in the reply.
struct ImageStatusView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
                .symbolEffect(.pulse)
            Text(verbatim: String(localized: "Creating an image"))
                .shimmering()
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Theme.secondaryText)
        .lineLimit(1)
    }
}

/// "Sources" pill with stacked site badges that opens the list of citations.
struct SourcesButton: View {
    let citations: [Citation]
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: -6) {
                    ForEach(citations.prefix(3)) { citation in
                        SourceBadge(citation: citation)
                    }
                }
                Text("Sources")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
            }
        }
        .buttonStyle(.glass)
        .sheet(isPresented: $isPresented) {
            SourcesSheet(citations: citations)
        }
    }
}

struct SourceBadge: View {
    let citation: Citation

    var body: some View {
        let host = citation.host ?? citation.url
        Text(verbatim: String(host.prefix(1)).uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Color(hue: Self.hue(for: host), saturation: 0.55, brightness: 0.72), in: Circle())
            .overlay(Circle().strokeBorder(Theme.background.opacity(0.6), lineWidth: 1))
    }

    /// Stable color per site (String.hashValue changes between launches).
    private static func hue(for host: String) -> Double {
        let value = host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Double(value % 360) / 360
    }
}

struct SourcesSheet: View {
    let citations: [Citation]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(citations) { citation in
                if let url = URL(string: citation.url) {
                    Link(destination: url) {
                        HStack(spacing: 12) {
                            SourceBadge(citation: citation)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: citation.title ?? citation.host ?? citation.url)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.primaryText)
                                    .lineLimit(2)
                                Text(verbatim: citation.host ?? citation.url)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct ErrorCard: View {
    let message: String
    let needsSignIn: Bool
    let onRetry: (() -> Void)?
    let onSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(verbatim: message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
            }
            .font(.subheadline)

            if needsSignIn {
                Button {
                    onSignIn()
                } label: {
                    Text("Sign in again")
                        .foregroundStyle(Theme.onProminent)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.prominentFill)
                .controlSize(.small)
            } else if let onRetry {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Theme.danger.opacity(0.16)), in: .rect(cornerRadius: 20))
    }
}
