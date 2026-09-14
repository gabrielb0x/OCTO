import OCTOCore
import SwiftUI

/// Custom instructions, personality and memory of the ChatGPT account.
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
            memorySection
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
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.white)
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

    private var memorySection: some View {
        Section {
            LabeledContent {
                onOffText(account.settings?.referencesSavedMemories)
            } label: {
                Label("Reference saved memories", systemImage: "brain")
            }
            LabeledContent {
                onOffText(account.settings?.referencesChatHistory)
            } label: {
                Label("Reference chat history", systemImage: "clock.arrow.circlepath")
            }
            NavigationLink {
                MemoriesView()
            } label: {
                LabeledContent {
                    if let count = account.memories?.memories.count {
                        Text(verbatim: "\(count)")
                    }
                } label: {
                    Label("Saved memories", systemImage: "list.bullet.rectangle")
                }
            }
        } header: {
            Text("Memory")
        } footer: {
            Text("When “Reference saved memories” is on, your saved memories are sent with the messages you write in OCTO. OCTO can't reference your chat history.")
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

    private func onOffText(_ value: Bool?) -> Text {
        switch value {
        case true?: return Text("On")
        case false?: return Text("Off")
        case nil: return Text(verbatim: "–")
        }
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
            } catch {
                saveError = ChatSession.describe(error)
            }
        }
    }

    private var saveErrorIsPresented: Binding<Bool> {
        Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
    }
}

/// The memories ChatGPT saved about the user.
struct MemoriesView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            if let snapshot = app.account.memories {
                if snapshot.memories.isEmpty {
                    Text("No saved memories.")
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Section {
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
                        }
                    } footer: {
                        Text("Memories are managed in ChatGPT.")
                    }
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
        .navigationTitle("Saved memories")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await app.account.refresh()
        }
    }
}
