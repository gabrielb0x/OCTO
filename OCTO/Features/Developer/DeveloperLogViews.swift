import OCTOCore
import SwiftUI
import UIKit

/// Every request OCTO made while developer mode was on, newest first.
struct NetworkLogView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case failures
        case account
        case codex
        case auth

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return String(localized: "All")
            case .failures: return String(localized: "Failures")
            case .account: return String(localized: "Account")
            case .codex: return "Codex"
            case .auth: return String(localized: "Sign-in")
            }
        }
    }

    @Environment(AppModel.self) private var app
    @State private var filter = Filter.all
    @State private var query = ""

    private var entries: [NetworkEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return app.developer.console.network.filter { entry in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .failures: matchesFilter = entry.isFailure
            case .account: matchesFilter = entry.category == .account
            case .codex: matchesFilter = entry.category == .codex
            case .auth: matchesFilter = entry.category == .auth
            }
            return matchesFilter && (needle.isEmpty || entry.displayURL.lowercased().contains(needle))
        }
    }

    var body: some View {
        List {
            if !app.developer.recordsNetwork {
                Label("Recording is paused.", systemImage: "pause.circle")
                    .foregroundStyle(Theme.warning)
            }
            if app.developer.simulatedFailure != .none {
                Label(String(localized: "Simulating: \(app.developer.simulatedFailure.title)"), systemImage: "bolt.horizontal.circle.fill")
                    .foregroundStyle(Theme.warning)
            }
            if entries.isEmpty {
                ContentUnavailableView("No requests", systemImage: "network", description: Text("Requests made by OCTO show up here while developer mode is on."))
            }
            ForEach(entries) { entry in
                NavigationLink {
                    NetworkEntryView(entryID: entry.id)
                } label: {
                    NetworkEntryRow(entry: entry)
                }
            }
        }
        .searchable(text: $query, prompt: Text("Filter by address"))
        .navigationTitle("Network")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: $filter) {
                        ForEach(Filter.allCases) { filter in
                            Text(verbatim: filter.title).tag(filter)
                        }
                    } label: {
                        Text("Filter")
                    }
                    Divider()
                    Button(role: .destructive) {
                        app.developer.console.clearNetwork()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel(Text("Filter"))
            }
        }
    }
}

struct NetworkEntryRow: View {
    let entry: NetworkEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(verbatim: entry.method)
                    .font(.caption.monospaced().weight(.bold))
                Text(verbatim: entry.statusLabel)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(entry.statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(entry.statusColor.opacity(0.15), in: Capsule())
                if entry.isSimulated {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
                }
                Spacer()
                Text(entry.startedAt, format: .dateTime.hour().minute().second())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.tertiaryText)
            }
            Text(verbatim: entry.url.path.isEmpty ? entry.displayURL : entry.url.path)
                .font(.footnote.monospaced())
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(verbatim: entry.url.host ?? "")
                if let duration = entry.durationLabel {
                    Text(verbatim: duration)
                }
                Text(verbatim: entry.sizeLabel)
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 2)
    }
}

struct NetworkEntryView: View {
    @Environment(AppModel.self) private var app
    let entryID: UUID

    var body: some View {
        if let entry = app.developer.console.network.first(where: { $0.id == entryID }) {
            List {
                Section("Request") {
                    CopyRow(title: "Address", value: entry.displayURL)
                    KeyValueRow(key: "method", value: entry.method)
                    KeyValueRow(key: "category", value: entry.category.rawValue)
                    KeyValueRow(key: "started", value: entry.startedAt.formatted(date: .omitted, time: .standard))
                    if entry.isSimulated {
                        Label("Simulated by developer mode", systemImage: "bolt.horizontal.circle.fill")
                            .foregroundStyle(Theme.warning)
                    }
                }

                Section("Response") {
                    KeyValueRow(key: "status", value: entry.statusLabel)
                    if let duration = entry.durationLabel {
                        KeyValueRow(key: "duration", value: duration)
                    }
                    KeyValueRow(key: "size", value: entry.sizeLabel)
                    if entry.streamEvents > 0 {
                        KeyValueRow(key: "events", value: "\(entry.streamEvents)")
                    }
                    if case .failed(let message) = entry.phase {
                        Text(verbatim: message)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Theme.danger)
                            .textSelection(.enabled)
                    }
                }

                if !entry.eventCounts.isEmpty {
                    Section("Stream events") {
                        ForEach(entry.eventCounts.sorted { $0.value > $1.value }, id: \.key) { item in
                            KeyValueRow(key: item.key, value: "\(item.value)")
                        }
                    }
                }

                headers("Request headers", entry.requestHeaders)
                if let body = entry.requestBody {
                    CodeSection(title: "Request body", text: body)
                }
                headers("Response headers", entry.responseHeaders)
                if let body = entry.responseBody {
                    CodeSection(title: "Response body", text: body)
                }
            }
            .navigationTitle(entry.url.lastPathComponent.isEmpty ? entry.method : entry.url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            UIPasteboard.general.string = entry.curlCommand
                            app.toasts.show(String(localized: "cURL command copied"), style: .info)
                        } label: {
                            Label("Copy as cURL", systemImage: "terminal")
                        }
                        ShareLink(item: report(for: entry)) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(Text("More options"))
                }
            }
        } else {
            ContentUnavailableView("Request not found", systemImage: "questionmark.circle")
        }
    }

    @ViewBuilder
    private func headers(_ title: LocalizedStringKey, _ values: [String: String]) -> some View {
        if !values.isEmpty {
            Section(title) {
                ForEach(values.keys.sorted(), id: \.self) { key in
                    KeyValueRow(key: key, value: values[key] ?? "")
                }
            }
        }
    }

    private func report(for entry: NetworkEntry) -> String {
        var lines = [
            "\(entry.method) \(entry.displayURL)",
            "status: \(entry.statusLabel)",
            "duration: \(entry.durationLabel ?? "–")",
            "",
            "## Request headers",
        ]
        lines += entry.requestHeaders.keys.sorted().map { "\($0): \(entry.requestHeaders[$0] ?? "")" }
        if let body = entry.requestBody {
            lines += ["", "## Request body", body]
        }
        lines += ["", "## Response headers"]
        lines += entry.responseHeaders.keys.sorted().map { "\($0): \(entry.responseHeaders[$0] ?? "")" }
        if let body = entry.responseBody {
            lines += ["", "## Response body", body]
        }
        if case .failed(let message) = entry.phase {
            lines += ["", "## Error", message]
        }
        return lines.joined(separator: "\n")
    }
}

private extension NetworkEntry {
    var statusLabel: String {
        switch phase {
        case .pending: return "…"
        case .streaming: return statusCode.map { "\($0) ⇣" } ?? "⇣"
        case .finished: return statusCode.map { String($0) } ?? "–"
        case .failed: return "ERR"
        }
    }

    var statusColor: Color {
        if case .failed = phase { return Theme.danger }
        switch statusCode ?? 0 {
        case 200..<300: return Theme.success
        case 300..<500: return Theme.warning
        case 500...: return Theme.danger
        default: return Theme.secondaryText
        }
    }

    var sizeLabel: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // "0 bytes" rather than "Zero KB".
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(responseBytes))
    }

    var durationLabel: String? {
        duration.map { "\(Int(($0 * 1_000).rounded())) ms" }
    }
}

/// App events recorded while developer mode is on, newest first.
struct EventLogView: View {
    @Environment(AppModel.self) private var app
    @State private var minimumLevel = DevLogEntry.Level.debug
    @State private var query = ""

    private var events: [DevLogEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        return app.developer.console.events.reversed().filter { event in
            event.level.rank >= minimumLevel.rank
                && (needle.isEmpty || event.message.lowercased().contains(needle) || event.category.lowercased().contains(needle))
        }
    }

    var body: some View {
        List {
            if events.isEmpty {
                ContentUnavailableView("No events", systemImage: "list.bullet.rectangle", description: Text("What OCTO does shows up here while developer mode is on."))
            }
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(verbatim: event.level.rawValue.uppercased())
                            .font(.caption2.monospaced().weight(.bold))
                            .foregroundStyle(event.level.color)
                        Text(verbatim: event.category)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Text(event.date, format: .dateTime.hour().minute().second())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    Text(verbatim: event.message)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
            }
        }
        .searchable(text: $query, prompt: Text("Filter the events"))
        .navigationTitle("Event log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(selection: $minimumLevel) {
                        ForEach(DevLogEntry.Level.allCases, id: \.self) { level in
                            Text(verbatim: level.rawValue.capitalized).tag(level)
                        }
                    } label: {
                        Text("Minimum level")
                    }
                    ShareLink(item: app.developer.console.eventsText()) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) {
                        app.developer.console.clearEvents()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(Text("More options"))
            }
        }
    }
}

private extension DevLogEntry.Level {
    var rank: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }

    var color: Color {
        switch self {
        case .debug: return Theme.tertiaryText
        case .info: return Theme.link
        case .warning: return Theme.warning
        case .error: return Theme.danger
        }
    }
}

/// Read-only GET requests to `chatgpt.com/backend-api` with the signed-in session.
struct APIConsoleView: View {
    @Environment(AppModel.self) private var app
    @State private var path = "me"
    @State private var response: ConsoleResponse?
    @State private var errorMessage: String?
    @State private var isSending = false

    private static let shortcuts = [
        "me",
        "settings/user",
        "accounts/check/v4-2023-04-27",
        "user_system_messages",
        "memories?include_memory_entries=true",
        "conversations?offset=0&limit=5&order=updated",
        "conversations/search?query=test",
        "gizmos/snorlax/sidebar?owned_only=true&conversations_per_gizmo=2&limit=5",
        "accounts/sessions",
        "accounts/security_settings/info",
        "accounts/mfa_info",
        "files/library/storage/usage",
        "codex/models?client_version=\(CodexBackend.clientVersion)",
        "wham/usage",
    ]

    var body: some View {
        List {
            Section {
                HStack(spacing: 4) {
                    Text(verbatim: "GET /backend-api/")
                        .font(.footnote.monospaced())
                        .foregroundStyle(Theme.secondaryText)
                    TextField(text: $path) {
                        Text(verbatim: "me")
                    }
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(send)
                }
                Menu {
                    ForEach(Self.shortcuts, id: \.self) { shortcut in
                        Button(shortcut) {
                            path = shortcut
                            send()
                        }
                    }
                } label: {
                    Label("Shortcuts", systemImage: "list.bullet")
                }
                Button(action: send) {
                    HStack {
                        Label("Send", systemImage: "paperplane")
                        if isSending {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isSending || ChatGPTAccountAPI.consoleURL(path: path) == nil)
            } footer: {
                Text("Read-only requests to chatgpt.com/backend-api with your session. Responses stay on this device.")
            }
            .foregroundStyle(Theme.primaryText)

            if let errorMessage {
                Section {
                    Text(verbatim: errorMessage)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Theme.danger)
                        .textSelection(.enabled)
                }
            }

            if let response {
                Section("Response") {
                    KeyValueRow(key: "status", value: "\(response.statusCode)")
                    KeyValueRow(key: "duration", value: "\(Int((response.duration * 1_000).rounded())) ms")
                    KeyValueRow(key: "size", value: ByteCountFormatter.string(fromByteCount: Int64(response.byteCount), countStyle: .file))
                }
                Section("Headers") {
                    ForEach(response.headers.keys.sorted(), id: \.self) { key in
                        KeyValueRow(key: key, value: response.headers[key] ?? "")
                    }
                }
                CodeSection(title: "Body", text: response.body.isEmpty ? "–" : response.body)
            }
        }
        .navigationTitle("API console")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send() {
        guard !isSending else { return }
        guard let url = ChatGPTAccountAPI.consoleURL(path: path) else {
            errorMessage = String(localized: "This address isn't a relative path of backend-api.")
            return
        }
        guard let service = app.store.service else {
            errorMessage = String(localized: "The console isn't available in demo mode.")
            return
        }
        isSending = true
        errorMessage = nil
        Task {
            do {
                response = try await service.consoleGET(url)
            } catch {
                response = nil
                errorMessage = DevLog.describe(error)
            }
            isSending = false
        }
    }
}
