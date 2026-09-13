import OCTOCore
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ComposerView: View {
    @Environment(AppModel.self) private var app
    @Bindable var session: ChatSession
    @FocusState private var isFocused: Bool
    @State private var dictation = DictationController()
    @State private var dictationPrefix = ""
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showFileImporter = false
    @State private var importError: String?

    var body: some View {
        VStack(spacing: 10) {
            if session.messages.isEmpty, session.draft.isEmpty, session.pendingAttachments.isEmpty, !isFocused {
                SuggestionChips { suggestion in
                    session.draft = suggestion
                    isFocused = true
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            GlassEffectContainer(spacing: 10) {
                HStack(alignment: .bottom, spacing: 10) {
                    attachMenu
                    inputField
                    trailingButton
                }
            }
        }
        .readableWidth()
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .animation(.smooth(duration: 0.25), value: session.pendingAttachments)
        .animation(.smooth(duration: 0.25), value: isFocused)
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
                Label("Files", systemImage: "doc")
            }
            if session.model.supportsWebSearch {
                Divider()
                Toggle(isOn: Binding(get: { session.conversation.webSearchEnabled }, set: { session.setWebSearch($0) })) {
                    Label("Web search", systemImage: "globe")
                }
            }
        } label: {
            Image(systemName: session.conversation.webSearchEnabled && session.model.supportsWebSearch ? "globe" : "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(session.conversation.webSearchEnabled && session.model.supportsWebSearch ? Theme.accent : Theme.primaryText)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text("Add attachments"))
    }

    private var inputField: some View {
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
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                }
            }

            HStack(alignment: .bottom, spacing: 2) {
                TextField(session.isTemporary ? LocalizedStringKey("Temporary message") : LocalizedStringKey("Ask anything"), text: $session.draft, axis: .vertical)
                    .font(.body)
                    .lineLimit(1...8)
                    .focused($isFocused)
                    .padding(.leading, 16)
                    .padding(.vertical, 13)
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        send()
                        return .handled
                    }

                Button(action: toggleDictation) {
                    Image(systemName: dictation.isActive ? "waveform" : "mic")
                        .symbolEffect(.variableColor.iterative, isActive: dictation.state == .listening)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(dictation.isActive ? Theme.accent : Theme.secondaryText)
                        .frame(width: 40, height: 46)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dictation.isActive ? Text("Stop dictation") : Text("Dictate"))
            }
            .padding(.trailing, 6)
        }
        .frame(minHeight: 48)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var trailingButton: some View {
        if session.isStreaming {
            GlassIconButton(systemImage: "stop.fill", label: "Stop generating", size: 48, prominent: true) {
                session.stop()
            }
        } else {
            GlassIconButton(systemImage: "arrow.up", label: "Send", size: 48, prominent: session.canSend, action: send)
                .disabled(!session.canSend)
                .opacity(session.canSend ? 1 : 0.6)
        }
    }

    // MARK: Actions

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
        dictationPrefix = existing.isEmpty ? "" : existing + " "
        let prefix = dictationPrefix
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

struct SuggestionChips: View {
    let onSelect: (String) -> Void

    private struct Suggestion: Identifiable {
        let systemImage: String
        let text: String
        var id: String { text }
    }

    private var suggestions: [Suggestion] {
        [
            Suggestion(systemImage: "lightbulb", text: String(localized: "Brainstorm ideas for a weekend project")),
            Suggestion(systemImage: "text.magnifyingglass", text: String(localized: "Summarize an article for me")),
            Suggestion(systemImage: "chevron.left.forwardslash.chevron.right", text: String(localized: "Help me debug my code")),
            Suggestion(systemImage: "airplane", text: String(localized: "Plan a 3-day trip to Lisbon")),
            Suggestion(systemImage: "graduationcap", text: String(localized: "Explain a complex topic simply")),
        ]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            onSelect(suggestion.text)
                        } label: {
                            Label {
                                Text(verbatim: suggestion.text)
                            } icon: {
                                Image(systemName: suggestion.systemImage)
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.primaryText)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
                .padding(.horizontal, 4)
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
