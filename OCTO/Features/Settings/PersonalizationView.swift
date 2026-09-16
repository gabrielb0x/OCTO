import OCTOCore
import SwiftUI

/// Custom instructions and personality of the ChatGPT account.
struct PersonalizationView: View {
    @Environment(AppModel.self) private var app
    @State private var draft = CustomInstructions()
    /// The account's instructions when the draft was made, to tell apart edits from updates.
    @State private var baseline: CustomInstructions?
    @State private var isSaving = false
    @State private var saveError: String?

    private var account: AccountStore { app.account }

    private var isEdited: Bool {
        baseline != nil && draft != baseline
    }

    var body: some View {
        Form {
            if baseline != nil {
                instructionsSections
            } else {
                loadingSection
            }
        }
        .navigationTitle("Personalization")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else if isEdited {
                    Button(action: save) {
                        Text("Save")
                            .foregroundStyle(Theme.onProminent)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.prominentFill)
                }
            }
        }
        .alert("Couldn't save", isPresented: saveErrorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .onAppear {
            if baseline == nil {
                loadDraft()
            }
        }
        .onChange(of: account.instructions) { _, _ in
            if !isEdited {
                loadDraft()
            }
        }
        .task {
            if account.instructions == nil {
                await account.refresh()
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var instructionsSections: some View {
        Section {
            Toggle(isOn: $draft.isEnabled) {
                Label("Enable customization", systemImage: "slider.horizontal.3")
            }
        } footer: {
            Text("Saved in your ChatGPT account and sent with the messages you write in OCTO.")
        }

        Section {
            Picker(selection: personalityBinding) {
                ForEach(personalityOptions) { option in
                    Text(verbatim: option.label).tag(option.key)
                }
            } label: {
                Label("Base style and tone", systemImage: "theatermasks")
            }
        } footer: {
            if let summary = personalityOptions.first(where: { $0.key == personalityBinding.wrappedValue })?.summary {
                Text(verbatim: summary)
            }
        }
        .disabled(!draft.isEnabled)

        if !account.traits.isEmpty {
            Section("Characteristics") {
                ForEach(account.traits) { trait in
                    Picker(selection: traitBinding(trait.key)) {
                        ForEach(trait.levels) { level in
                            Text(verbatim: level.label).tag(level.key)
                        }
                    } label: {
                        Text(verbatim: trait.label)
                    }
                }
            }
            .disabled(!draft.isEnabled)
        }

        Section {
            TextEditor(text: $draft.responseStyle)
                .frame(minHeight: 110)
        } header: {
            Text("Custom instructions")
        } footer: {
            Text("For example: concise, friendly, with examples, always in French.")
        }
        .disabled(!draft.isEnabled)

        Section("About you") {
            TextField("Nickname", text: $draft.nickname)
            TextField("Occupation", text: $draft.occupation)
            VStack(alignment: .leading, spacing: 6) {
                Text("More about you")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                TextEditor(text: $draft.aboutUser)
                    .frame(minHeight: 110)
            }
        }
        .disabled(!draft.isEnabled)
    }

    @ViewBuilder
    private var loadingSection: some View {
        Section {
            if case .failed(let message) = account.state {
                VStack(alignment: .leading, spacing: 10) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                    Button("Try again") {
                        Task { await account.refresh() }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
    }

    // MARK: Helpers

    private var personalityOptions: [PersonalityOption] {
        var options = account.personalities
        if options.isEmpty {
            options = [PersonalityOption(key: "default", label: String(localized: "Default"))]
        }
        let current = draft.personality ?? "default"
        if !options.contains(where: { $0.key == current }) {
            options.append(PersonalityOption(key: current, label: current.capitalized))
        }
        return options
    }

    private var personalityBinding: Binding<String> {
        Binding(get: { draft.personality ?? "default" }, set: { draft.personality = $0 })
    }

    private func traitBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { draft.traits[key] ?? "default" },
            set: { draft.traits[key] = $0 == "default" ? nil : $0 }
        )
    }

    private func loadDraft() {
        guard let instructions = account.instructions else { return }
        draft = instructions
        baseline = instructions
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        let edited = draft
        Task {
            defer { isSaving = false }
            do {
                try await account.saveInstructions(edited)
                loadDraft()
                app.toasts.show(String(localized: "Personalization saved"))
            } catch {
                saveError = ChatSession.describe(error)
            }
        }
    }

    private var saveErrorIsPresented: Binding<Bool> {
        Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
    }
}

/// Memory settings of the ChatGPT account and the memories it saved.
struct MemoryView: View {
    @Environment(AppModel.self) private var app
    @State private var memoryToDelete: SavedMemory?

    var body: some View {
        List {
            Section {
                AccountSettingToggle(feature: .referencesSavedMemories, title: "Reference saved memories", systemImage: "brain")
                AccountSettingToggle(feature: .referencesChatHistory, title: "Reference chat history", systemImage: "clock.arrow.circlepath")
            } footer: {
                Text("These are the switches of your ChatGPT account, changed here as they would be in ChatGPT. When “Reference saved memories” is on, your saved memories are sent with the messages you write in OCTO. OCTO can't reference your chat history.")
            }

            if let snapshot = app.account.memories {
                if let used = snapshot.usedTokens, let capacity = snapshot.maxTokens, capacity > 0 {
                    Section {
                        let fraction = min(Double(used) / Double(capacity), 1)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Memory used")
                                Spacer()
                                Text(verbatim: "\(Int((fraction * 100).rounded())) %")
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            ProgressView(value: fraction)
                                .tint(fraction >= 0.9 ? Theme.danger : Theme.primaryText)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    if snapshot.memories.isEmpty {
                        Text("No saved memories.")
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(snapshot.memories) { memory in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: memory.content)
                                if let updatedAt = memory.updatedAt {
                                    Text(updatedAt, format: .dateTime.day().month().year())
                                        .font(.caption)
                                        .foregroundStyle(Theme.tertiaryText)
                                }
                            }
                            .padding(.vertical, 2)
                            .swipeActions {
                                Button(role: .destructive) {
                                    memoryToDelete = memory
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    memoryToDelete = memory
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Saved memories")
                } footer: {
                    Text("Swipe a memory to delete it from your ChatGPT account. New memories are saved by ChatGPT while you chat in its apps.")
                }
            } else if case .failed(let message) = app.account.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.danger)
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete this memory?",
            isPresented: deleteIsPresented,
            titleVisibility: .visible,
            presenting: memoryToDelete
        ) { memory in
            Button("Delete", role: .destructive) {
                delete(memory)
            }
        } message: { memory in
            Text(verbatim: memory.content)
        }
        .detachedRefreshable {
            await app.account.refresh()
        }
        .task {
            if app.account.memories == nil {
                await app.account.refresh()
            }
        }
    }

    /// Deletes the memory in the ChatGPT account; the row is already gone from the list.
    private func delete(_ memory: SavedMemory) {
        Task {
            do {
                try await app.account.deleteMemory(id: memory.id)
                app.toasts.show(String(localized: "The memory has been deleted"))
            } catch {
                app.toasts.show(ChatSession.describe(error), style: .failure)
            }
        }
    }

    private var deleteIsPresented: Binding<Bool> {
        Binding(get: { memoryToDelete != nil }, set: { if !$0 { memoryToDelete = nil } })
    }
}
