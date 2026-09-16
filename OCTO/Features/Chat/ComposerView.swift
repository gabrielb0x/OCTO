import OCTOCore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// ChatGPT-style message bar made of Liquid Glass: a round + button next to a glass capsule
/// holding the text field, dictation and the voice, send or stop button.
struct ComposerView: View {
    @Environment(AppModel.self) private var app
    @Bindable var session: ChatSession
    let onStartVoice: () -> Void

    @FocusState private var isFocused: Bool
    @State private var dictation = DictationController()
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var importError: String?
    /// Shift-Return on a hardware keyboard adds a line even when Return sends.
    @State private var allowsNextNewline = false

    private static let barHeight: CGFloat = 50

    private var showsSuggestions: Bool {
        app.settings.showsSuggestions && session.isBlank && !session.isTemporary && session.draft.isEmpty && session.pendingAttachments.isEmpty && !isFocused && !dictation.showsRecording
    }

    private var isWebSearchOn: Bool {
        session.conversation.webSearchEnabled && session.model.supportsWebSearch
    }

    var body: some View {
        VStack(spacing: 10) {
            if showsSuggestions {
                suggestions
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            field
        }
        .readableWidth()
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(.smooth(duration: 0.25), value: session.pendingAttachments)
        .animation(.smooth(duration: 0.25), value: showsSuggestions)
        .animation(.smooth(duration: 0.2), value: isWebSearchOn)
        .animation(.smooth(duration: 0.2), value: dictation.showsRecording)
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoSelection, maxSelectionCount: 4, matching: .images)
        .onChange(of: photoSelection) { _, items in
            loadPhotos(items)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                session.addImage(image)
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: Self.importableTypes, allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .alert("Couldn't attach file", isPresented: importErrorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .alert("Dictation unavailable", isPresented: dictationErrorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(dictation.errorMessage ?? "")
        }
        .onDisappear {
            dictation.stop()
        }
    }

    // MARK: Pieces

    /// The starter prompts of a new chat: the list of the ChatGPT app, or glass chips.
    @ViewBuilder
    private var suggestions: some View {
        switch app.settings.suggestionStyle {
        case .list:
            SuggestionList(supportsWebSearch: session.model.supportsWebSearch, onSelect: apply)
        case .chips:
            SuggestionChips { prompt in
                session.draft = prompt
                isFocused = true
            }
        }
    }

    private var attachMenu: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Label("Camera", systemImage: "camera")
                }
                .disabled(!session.model.acceptsImages)
            }
            Button {
                showPhotoPicker = true
            } label: {
                Label("Photos", systemImage: "photo.on.rectangle.angled")
            }
            .disabled(!session.model.acceptsImages)
            Button {
                showFileImporter = true
            } label: {
                Label("Files", systemImage: "paperclip")
            }
            if session.model.supportsWebSearch {
                Divider()
                Toggle(isOn: Binding(get: { session.conversation.webSearchEnabled }, set: { session.setWebSearch($0) })) {
                    Label("Web search", systemImage: "globe")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 46, height: Self.barHeight)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Add attachments"))
    }

    /// The glass capsule of the ChatGPT app, holding the + button, what you write, dictation and
    /// the voice, send or stop button. Round while it holds one line, a rounded rectangle as the
    /// message grows.
    private var field: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !session.pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(session.pendingAttachments) { attachment in
                            PendingAttachmentView(attachment: attachment) {
                                session.removeAttachment(attachment.id)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
            }

            if dictation.showsRecording {
                DictationRecordingBar(dictation: dictation, accent: app.settings.accentStyle, onCancel: dictation.cancel, onDone: finishDictation)
                    .transition(.opacity)
            } else {
                HStack(alignment: .bottom, spacing: 0) {
                    attachMenu
                    if isWebSearchOn {
                        webSearchChip
                    }
                    TextField(placeholder, text: $session.draft, axis: .vertical)
                        .font(.body)
                        .lineLimit(1...8)
                        .focused($isFocused)
                        .autocorrectionDisabled(!app.settings.correctsSpelling)
                        .padding(.leading, isWebSearchOn ? 6 : 2)
                        .padding(.vertical, 14)
                        .onKeyPress(.return, phases: .down) { press in
                            handleReturn(press)
                        }
                        .onChange(of: session.draft) { old, new in
                            sendIfReturnWasTyped(old: old, new: new)
                        }
                    dictationButton
                    trailingButton
                }
                .padding(.trailing, 3)
            }
        }
        .frame(minHeight: Self.barHeight)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Self.barHeight / 2, style: .continuous))
    }

    private var placeholder: LocalizedStringKey {
        if session.isTemporary { return "Temporary message" }
        return isWebSearchOn ? "Search the web" : "Ask ChatGPT"
    }

    private var webSearchChip: some View {
        Button {
            session.setWebSearch(false)
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(app.settings.accentStyle.link)
                .frame(width: 34, height: 34)
                .background(app.settings.accentStyle.link.opacity(0.18), in: Circle())
                .padding(.leading, 8)
                .frame(height: Self.barHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel(Text("Turn off web search"))
    }

    private var dictationButton: some View {
        Button(action: toggleDictation) {
            Image(systemName: dictation.state == .listening ? "waveform" : "mic")
                .symbolEffect(.variableColor.iterative, isActive: dictation.state == .listening)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(dictation.isActive ? app.settings.accentStyle.link : Theme.primaryText)
                .frame(width: 40, height: Self.barHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(dictation.state == .starting)
        .accessibilityLabel(dictation.isActive ? Text("Stop dictation") : Text("Dictate"))
    }

    /// Voice mode when the composer is empty, send once there is something to send, stop while generating.
    private var trailingButton: some View {
        Button(action: trailingAction) {
            Image(systemName: trailingSymbol)
                .font(.system(size: session.isStreaming ? 13 : 16, weight: .bold))
                .foregroundStyle(app.settings.accentStyle.onFill)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 38, height: 38)
                .background(app.settings.accentStyle.fill, in: Circle())
                .frame(width: 44, height: Self.barHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(trailingLabel)
    }

    private var trailingSymbol: String {
        if session.isStreaming { return "stop.fill" }
        return session.canSend ? "arrow.up" : "waveform"
    }

    private var trailingLabel: Text {
        if session.isStreaming { return Text("Stop generating") }
        return session.canSend ? Text("Send") : Text("Voice mode")
    }

    // MARK: Actions

    /// A tapped suggestion starts the message, or turns on web search, and opens the keyboard.
    private func apply(_ suggestion: ChatSuggestion) {
        switch suggestion.action {
        case .prompt(let text):
            session.draft = text
        case .webSearch:
            session.setWebSearch(true)
        }
        isFocused = true
    }

    private func trailingAction() {
        if session.isStreaming {
            session.stop()
        } else if session.canSend {
            send(dismissingKeyboard: true)
        } else {
            dictation.stop()
            isFocused = false
            onStartVoice()
        }
    }

    /// Tapping the send button also puts the keyboard away, so the whole reply is in sight.
    /// The Return key keeps it up: you're likely writing another message right after.
    private func send(dismissingKeyboard: Bool = false) {
        guard session.canSend else { return }
        dictation.stop()
        if dismissingKeyboard {
            isFocused = false
        }
        session.send()
    }

    private func handleReturn(_ press: KeyPress) -> KeyPress.Result {
        let sends = app.settings.sendsWithReturn ? !press.modifiers.contains(.shift) : press.modifiers.contains(.command)
        guard sends else {
            if app.settings.sendsWithReturn {
                allowsNextNewline = true
            }
            return .ignored
        }
        send()
        return .handled
    }

    /// With "Send with Return", the Return key of the on-screen keyboard sends too.
    private func sendIfReturnWasTyped(old: String, new: String) {
        guard app.settings.sendsWithReturn, new.count == old.count + 1, new.hasSuffix("\n"), new.dropLast() == old[...] else { return }
        guard !allowsNextNewline else {
            allowsNextNewline = false
            return
        }
        session.draft = old
        send()
    }

    private func toggleDictation() {
        if dictation.isActive {
            dictation.stop()
            return
        }
        if app.settings.transcriptionEngine == .chatGPT, app.accountService != nil {
            Task {
                await dictation.startRecording(onLimit: finishDictation)
            }
        } else {
            let existing = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = existing.isEmpty ? "" : existing + " "
            Task {
                await dictation.startOnDevice { transcript in
                    session.draft = prefix + transcript
                }
            }
        }
    }

    private func finishDictation() {
        guard let service = app.accountService else {
            dictation.cancel()
            return
        }
        dictation.finishRecording(
            transcribe: { audio, milliseconds in
                try await service.transcribe(audio: audio, durationMilliseconds: milliseconds)
            },
            onTranscript: { text, onDevice in
                insertDictation(text)
                if onDevice {
                    app.toasts.show(String(localized: "Transcribed on this device: ChatGPT couldn't do it"), style: .info, systemImage: "iphone")
                }
            }
        )
    }

    private func insertDictation(_ text: String) {
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else {
            app.toasts.show(String(localized: "Nothing was heard"), style: .info, systemImage: "mic.slash")
            return
        }
        let existing = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        session.draft = existing.isEmpty ? spoken : existing + " " + spoken
        isFocused = true
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        photoSelection = []
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    session.addImage(image)
                }
            }
        }
    }

    static let importableTypes: [UTType] = {
        var types: [UTType] = [.plainText, .utf8PlainText, .sourceCode, .json, .commaSeparatedText, .xml, .yaml, .html, .propertyList]
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        return types
    }()

    private func importFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            for url in urls {
                let isAccessing = url.startAccessingSecurityScopedResource()
                defer {
                    if isAccessing { url.stopAccessingSecurityScopedResource() }
                }
                let name = url.lastPathComponent
                guard let data = try? Data(contentsOf: url) else {
                    importError = String(localized: "“\(name)” could not be read.")
                    continue
                }
                guard data.count <= 400_000 else {
                    importError = String(localized: "“\(name)” is too large. Text files up to 400 KB are supported.")
                    continue
                }
                guard let text = String(data: data, encoding: .utf8) else {
                    importError = String(localized: "“\(name)” is not a text file.")
                    continue
                }
                session.addTextFile(name: name, text: text)
            }
        }
    }

    private var importErrorIsPresented: Binding<Bool> {
        Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
    }

    private var dictationErrorIsPresented: Binding<Bool> {
        Binding(get: { dictation.errorMessage != nil }, set: { if !$0 { dictation.clearError() } })
    }
}

/// The message bar while ChatGPT dictation records: the level of your voice, the time, and
/// buttons to cancel or to have it written down.
struct DictationRecordingBar: View {
    let dictation: DictationController
    let accent: AccentStyle
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 44, height: 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Cancel dictation"))

            if dictation.state == .transcribing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Transcribing…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LevelMeter(levels: dictation.levels)
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                if let start = dictation.recordingStartedAt {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize()
                }
            }

            Button(action: onDone) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent.onFill)
                    .frame(width: 38, height: 38)
                    .background(accent.fill, in: Circle())
                    .frame(width: 44, height: 50)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(dictation.state != .recording)
            .opacity(dictation.state == .recording ? 1 : 0.4)
            .accessibilityLabel(Text("Transcribe"))
        }
        .padding(.trailing, 3)
    }
}

/// The recent loudness of the microphone as thin bars, newest on the right.
struct LevelMeter: View {
    let levels: [Double]

    var body: some View {
        Canvas { context, size in
            let barWidth: CGFloat = 3
            let gap: CGFloat = 3
            let fitting = max(Int((size.width + gap) / (barWidth + gap)), 0)
            let recent = levels.suffix(fitting)
            var x = size.width - CGFloat(recent.count) * (barWidth + gap) + gap
            for level in recent {
                let height = max(3, size.height * level)
                let bar = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: barWidth / 2), with: .color(Theme.primaryText.opacity(0.8)))
                x += barWidth + gap
            }
        }
        .accessibilityHidden(true)
    }
}

struct PendingAttachmentView: View {
    let attachment: PendingAttachment
    let onRemove: () -> Void
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                switch attachment.content {
                case .image:
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Theme.surfaceElevated
                    }
                case .text:
                    VStack(spacing: 4) {
                        Image(systemName: "doc.text.fill")
                            .font(.title3)
                        Text(verbatim: attachment.name)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .padding(6)
                    .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(width: 64, height: 64)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.75))
                    .font(.system(size: 20))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .accessibilityLabel(Text("Remove attachment"))
        }
        .padding(.top, 6)
        .padding(.trailing, 6)
        .task(id: attachment.id) {
            if case .image(let data) = attachment.content {
                thumbnail = ImageProcessing.thumbnail(from: data, maxPixelSize: 200)
            }
        }
    }
}

/// One starter prompt of a new chat.
struct ChatSuggestion: Identifiable {
    enum Action {
        /// Starts the message, which you finish yourself.
        case prompt(String)
        /// Turns on web search, like the "Search the web" row of the ChatGPT app.
        case webSearch
    }

    let title: String
    let systemImage: String
    let action: Action

    var id: String { title }
}

/// The starter prompts of the ChatGPT app: an icon and a few words, one per line above the message bar.
struct SuggestionList: View {
    let supportsWebSearch: Bool
    let onSelect: (ChatSuggestion) -> Void

    private var suggestions: [ChatSuggestion] {
        var list = [
            ChatSuggestion(title: String(localized: "Create an image"), systemImage: "photo", action: .prompt(String(localized: "Create an image of") + " ")),
            ChatSuggestion(title: String(localized: "Write or edit"), systemImage: "pencil", action: .prompt(String(localized: "Help me write") + " ")),
        ]
        if supportsWebSearch {
            list.append(ChatSuggestion(title: String(localized: "Search the web"), systemImage: "globe", action: .webSearch))
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(suggestions) { suggestion in
                Button {
                    onSelect(suggestion)
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: suggestion.systemImage)
                            .font(.system(size: 19, weight: .regular))
                            .frame(width: 26)
                        Text(verbatim: suggestion.title)
                            .font(.body)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Theme.primaryText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .contentShape(.rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Starter prompts above the composer of a new chat, as native glass buttons.
struct SuggestionChips: View {
    let onSelect: (String) -> Void

    private struct Suggestion: Identifiable {
        let title: String
        let prompt: String
        let systemImage: String
        let color: Color
        var id: String { title }
    }

    private var suggestions: [Suggestion] {
        [
            Suggestion(title: String(localized: "Brainstorm"), prompt: String(localized: "Brainstorm ideas for a weekend project"), systemImage: "lightbulb", color: .yellow),
            Suggestion(title: String(localized: "Code"), prompt: String(localized: "Help me debug my code"), systemImage: "chevron.left.forwardslash.chevron.right", color: .purple),
            Suggestion(title: String(localized: "Summarize text"), prompt: String(localized: "Summarize an article for me"), systemImage: "text.alignleft", color: .orange),
            Suggestion(title: String(localized: "Make a plan"), prompt: String(localized: "Plan a 3-day trip to Lisbon"), systemImage: "list.bullet.clipboard", color: .mint),
            Suggestion(title: String(localized: "Get advice"), prompt: String(localized: "Explain a complex topic simply"), systemImage: "graduationcap", color: .cyan),
        ]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            onSelect(suggestion.prompt)
                        } label: {
                            Label {
                                Text(verbatim: suggestion.title)
                                    .foregroundStyle(Theme.primaryText)
                            } icon: {
                                Image(systemName: suggestion.systemImage)
                                    .foregroundStyle(suggestion.color)
                            }
                            .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .scrollClipDisabled()
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
