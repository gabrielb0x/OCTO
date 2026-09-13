import OCTOCore
import SwiftUI
import UIKit

struct MessageRow: View {
    let message: ChatMessage
    let session: ChatSession
    let isLast: Bool
    let onEdit: () -> Void

    var body: some View {
        switch message.role {
        case .user:
            UserMessageView(message: message, canEdit: !session.isStreaming, onEdit: onEdit)
        case .assistant:
            AssistantMessageView(message: message, session: session, isLast: isLast)
        }
    }
}

struct UserMessageView: View {
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
                    .padding(.vertical, 11)
                    .background(Theme.userBubble, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.text
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
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
        .padding(.leading, 44)
    }
}

struct AttachmentGallery: View {
    @Environment(AppModel.self) private var app
    let attachments: [MessageAttachment]

    var body: some View {
        let imageSide: CGFloat = attachments.count == 1 ? 200 : 116
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    switch attachment.kind {
                    case .image:
                        Group {
                            if let image = AttachmentThumbnails.image(for: attachment, files: app.store.files) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Theme.surfaceElevated
                            }
                        }
                        .frame(width: imageSide, height: imageSide)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    case .text:
                        FileChip(name: attachment.displayName ?? "file", byteCount: attachment.byteCount)
                    }
                }
            }
        }
        .defaultScrollAnchor(.trailing)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct FileChip: View {
    let name: String
    let byteCount: Int?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
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
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct AssistantMessageView: View {
    @Environment(AppModel.self) private var app
    let message: ChatMessage
    let session: ChatSession
    let isLast: Bool
    @State private var copied = false

    private var isActive: Bool { message.status == .streaming }
    private var activity: ChatSession.Activity { isActive ? session.activity : .idle }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if activity == .thinking || !message.reasoning.isEmpty || message.reasoningDuration != nil {
                ReasoningView(
                    reasoning: message.reasoning,
                    duration: message.reasoningDuration,
                    isThinking: activity == .thinking,
                    canExpand: app.settings.showReasoning && !message.reasoning.isEmpty
                )
            }

            if activity == .searching || !message.searchQueries.isEmpty {
                SearchStatusView(queries: message.searchQueries, isSearching: activity == .searching)
            }

            if message.text.isEmpty {
                if activity == .waiting || activity == .writing {
                    PulsingDot()
                        .padding(.vertical, 4)
                }
            } else {
                MarkdownView(text: message.text)
                    .textSelection(.enabled)
            }

            if !message.citations.isEmpty, !isActive {
                SourcesView(citations: message.citations)
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
        HStack(spacing: 0) {
            actionButton(copied ? "checkmark" : "doc.on.doc", label: "Copy") {
                UIPasteboard.general.string = message.text
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            actionButton(app.speech.speakingMessageID == message.id ? "stop.circle" : "speaker.wave.2", label: "Read aloud") {
                app.speech.toggle(messageID: message.id, markdown: message.text, rate: app.settings.speechRate)
            }
            if isLast {
                actionButton("arrow.clockwise", label: "Regenerate") {
                    session.regenerate(message.id)
                }
                .disabled(session.isStreaming)
            }
            ShareLink(item: message.text) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text("Share"))

            Spacer(minLength: 8)

            if let modelID = message.modelID {
                Text(verbatim: app.models.first(where: { $0.id == modelID })?.displayName ?? modelID)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.secondaryText)
        .buttonStyle(.plain)
        .padding(.leading, -8)
        .sensoryFeedback(.success, trigger: copied) { _, isCopied in
            isCopied && app.settings.hapticsEnabled
        }
    }

    private func actionButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
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

struct SourcesView: View {
    let citations: [Citation]
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(citations) { citation in
                        Button {
                            if let url = URL(string: citation.url) {
                                openURL(url)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.caption2.weight(.bold))
                                Text(verbatim: citation.host ?? citation.url)
                                    .lineLimit(1)
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .help(citation.title ?? citation.url)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .scrollClipDisabled()
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
                Button("Sign in again", action: onSignIn)
                    .buttonStyle(.glassProminent)
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
        .glassEffect(.regular.tint(Theme.danger.opacity(0.16)), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
