import OCTOCore
import SwiftUI

/// The models Codex offers the account: which one new chats start with, what each is for, how
/// deep it can think and how fast it can answer — and those the plan doesn't include. OCTO asks
/// Codex's catalog (`codex/models`), keeps the models it gives the plan, and leaves out any Codex
/// turns down when a message is sent.
struct ModelsSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        List {
            Section {
                ForEach(app.availableModels) { model in
                    Button {
                        app.settings.defaultModelID = model.id
                    } label: {
                        modelRow(model, isDefault: model.id == app.defaultModel.id)
                    }
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityAddTraits(model.id == app.defaultModel.id ? [.isButton, .isSelected] : .isButton)
                }
            } header: {
                Text("Offered to your plan")
            } footer: {
                Text("New chats start with the model chosen here. Each chat can switch model, thinking and speed from the top of the screen.")
            }

            if !app.unavailableModels.isEmpty {
                Section {
                    ForEach(app.unavailableModels) { model in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: model.displayName)
                                .foregroundStyle(Theme.secondaryText)
                            Text(app.refusedModelIDs.contains(model.id)
                                ? LocalizedStringKey("Codex turned it down for your account")
                                : LocalizedStringKey("Codex doesn't offer it to your plan"))
                                .font(.caption)
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Not included in your plan")
                }
            }

            Section {
                Button {
                    Task { await app.refreshModels() }
                } label: {
                    HStack {
                        Label("Check again", systemImage: "arrow.clockwise")
                        if app.isRefreshingModels {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .foregroundStyle(Theme.primaryText)
                .disabled(app.isRefreshingModels)
                if let updatedAt = app.modelsUpdatedAt {
                    LabeledContent {
                        Text(updatedAt, format: .relative(presentation: .named))
                    } label: {
                        Text("Last checked")
                    }
                }
                if let error = app.modelsError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
            } footer: {
                Text("OCTO asks Codex which models your account can use, keeps those it gives your plan, and leaves out any it turns down when a message is sent.")
            }
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .detachedRefreshable {
            await app.refreshModels()
        }
    }

    private func modelRow(_ model: ModelDescriptor, isDefault: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: model.displayName)
                    .font(.body.weight(.medium))
                if let summary = model.summary {
                    Text(verbatim: ModelText.localized(summary))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                if let details = details(of: model) {
                    Text(verbatim: details)
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            Spacer(minLength: 0)
            if isDefault {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(app.settings.accentStyle.link)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }

    /// How deep the model thinks and how fast it can answer, in a line.
    private func details(of model: ModelDescriptor) -> String? {
        var parts: [String] = []
        if let lightest = model.reasoningEfforts.first?.effort, let deepest = model.reasoningEfforts.last?.effort {
            if lightest == deepest {
                parts.append(ReasoningEffortLabel.title(lightest))
            } else {
                parts.append(String(localized: "Thinking: \(ReasoningEffortLabel.title(lightest)) to \(ReasoningEffortLabel.title(deepest))"))
            }
        }
        let speeds = model.speedTiers.map { ModelText.localized($0.name) }
        if !speeds.isEmpty {
            parts.append(speeds.joined(separator: ", "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
