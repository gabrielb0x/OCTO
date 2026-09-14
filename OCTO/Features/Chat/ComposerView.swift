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

    private static let barHeight: CGFloat = 50

    private var showsSuggestions: Bool {
        session.isBlank && !session.isTemporary && session.draft.isEmpty && session.pendingAttachments.isEmpty && !isFocused
    }

    private var isWebSearchOn: Bool {
        session.conversation.webSearchEnabled && session.model.supportsWebSearch
    }

    var body: some View {
        VStack(spacing: 12) {
            if showsSuggestions {
                SuggestionChips { suggestion in
                    session.draft = suggestion
                    isFocused = true
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            GlassEffectContainer(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    attachMenu
                    field
                }
            }
        }
        .readableWidth()
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .animation(.smooth(duration: 0.25), value: session.pendingAttachments)
        .animation(.smooth(duration: 0.25), value: showsSuggestions)
        .animation(.smooth(duration: 0.2), value: isWebSearchOn)
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
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(Theme.primaryText)
                .frame(width: Self.barHeight, height: Self.barHeight)
                .contentShape(Circle())
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("Add attachments"))
    }

    /// The glass capsule: round while it holds one line, a rounded rectangle as the message grows.
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

            HStack(alignment: .bottom, spacing: 0) {
                if isWebSearchOn {
                    webSearchChip
                }
                TextField(placeholder, text: $session.draft, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...8)
                    .focused($isFocused)
                    .padding(.leading, isWebSearchOn ? 6 : 18)
                    .padding(.vertical, 14)
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        send()
                        return .handled
                    }
                dictationButton
                trailingButton
            }
            .padding(.trailing, 3)
        }
        .frame(minHeight: Self.barHeight)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Self.barHeight / 2, style: .continuous))
    }

    private var placeholder: LocalizedStringKey {
        if session.isTemporary { return "Temporary message" }
        return isWebSearchOn ? "Search the web" : "Ask anything"
    }

    private var webSearchChip: some View {
        Button {
            session.setWebSearch(false)
        } label: {
            Image(systemName: "globe")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.link)
                .frame(width: 34, height: 34)
                .background(Theme.link.opacity(0.18), in: Circle())
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
            Image(systemName: dictation.isActive ? "waveform" : "mic")
                .symbolEffect(.variableColor.iterative, isActive: dictation.state == .listening)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(dictation.isActive ? Theme.link : Theme.primaryText)
                .frame(width: 40, height: Self.barHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dictation.isActive ? Text("Stop dictation") : Text("Dictate"))
    }

    /// Voice mode when the composer is empty, send once there is something to send, stop while generating.
    private var trailingButton: some View {
        Button(action: trailingAction) {
            Image(systemName: trailingSymbol)
                .font(.system(size: session.isStreaming ? 13 : 16, weight: .bold))
                .foregroundStyle(.black)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 38, height: 38)
                .background(.white, in: Circle())
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

    private func trailingAction() {
        if session.isStreaming {
            session.stop()
        } else if session.canSend {
            send()
        } else {
            dictation.stop()
            isFocused = false
            onStartVoice()
        }
    }

    private func send() {
        guard session.canSend else { return }
        dictation.stop()
        session.send()
    }

    private func toggleDictation() {
        if dictation.isActive {
            dictation.stop()
            return
        }
        let existing = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = existing.isEmpty ? "" : existing + " "
        Task {
            await dictation.start { transcript in
                session.draft = prefix + transcript
            }
        }
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
