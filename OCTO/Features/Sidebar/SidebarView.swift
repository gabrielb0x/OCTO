import OCTOCore
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    let selectedID: UUID?
    let onSelect: (UUID) -> Void
    let onNewChat: () -> Void
    let onDelete: (UUID) -> Void
    let onOpenSettings: () -> Void

    @State private var query = ""
    @State private var renameTarget: ConversationSummary?
    @State private var renameText = ""
    @State private var deleteTarget: ConversationSummary?

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if isSearching {
                        let results = app.store.search(query)
                        if results.isEmpty {
                            placeholder(title: "No results", systemImage: "magnifyingglass")
                        } else {
                            sectionHeader(String(localized: "Results"))
                            ForEach(results) { row($0) }
                        }
                    } else {
                        let sections = ConversationGrouping.sections(for: app.store.summaries)
                        if sections.isEmpty {
                            placeholder(title: "Your chats will appear here", systemImage: "bubble.left.and.bubble.right")
                        }
                        ForEach(sections) { section in
                            sectionHeader(title(for: section.bucket))
                            ForEach(section.conversations) { row($0) }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.immediately)

            footer
        }
        .background(Theme.sidebarBackground.ignoresSafeArea())
        .alert("Rename chat", isPresented: renameIsPresented) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let target = renameTarget {
                    app.store.rename(id: target.id, to: renameText)
                }
            }
        }
        .confirmationDialog("Delete this chat?", isPresented: deleteIsPresented, titleVisibility: .visible, presenting: deleteTarget) { target in
            Button("Delete", role: .destructive) {
                onDelete(target.id)
            }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Header & footer

    private var header: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.secondaryText)
                    TextField("Search chats", text: $query)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.tertiaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Clear search"))
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .glassEffect(.regular, in: .capsule)

                GlassIconButton(systemImage: "square.and.pencil", label: "New chat", size: 46, action: onNewChat)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        Button(action: onOpenSettings) {
            HStack(spacing: 12) {
                AccountAvatar(account: app.auth.account, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: accountTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(verbatim: accountSubtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityLabel(Text("Settings"))
    }

    private var accountTitle: String {
        guard let account = app.auth.account else { return "OCTO" }
        switch account.method {
        case .apiKey:
            return String(localized: "OpenAI API key")
        case .chatGPT:
            return account.email ?? String(localized: "ChatGPT account")
        }
    }

    private var accountSubtitle: String {
        guard let account = app.auth.account else { return "" }
        switch account.method {
        case .apiKey:
            return String(localized: "Pay as you go")
        case .chatGPT:
            if let plan = ChatGPTPlan.displayName(for: account.planType) {
                return String(localized: "ChatGPT \(plan)")
            }
            return String(localized: "ChatGPT")
        }
    }

    // MARK: Rows

    private func row(_ summary: ConversationSummary) -> some View {
        let isSelected = summary.id == selectedID
        return Button {
            onSelect(summary.id)
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: summary.title.isEmpty ? String(localized: "New chat") : summary.title)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 0)
                if summary.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.white.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                app.store.setPinned(!summary.isPinned, id: summary.id)
            } label: {
                Label(summary.isPinned ? LocalizedStringKey("Unpin") : LocalizedStringKey("Pin"), systemImage: summary.isPinned ? "pin.slash" : "pin")
            }
            Button {
                renameText = summary.title
                renameTarget = summary
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Divider()
            Button(role: .destructive) {
                deleteTarget = summary
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(verbatim: title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.tertiaryText)
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 6)
    }

    private func placeholder(title: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.subheadline)
        }
        .foregroundStyle(Theme.tertiaryText)
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func title(for bucket: ConversationBucket) -> String {
        switch bucket {
        case .pinned:
            return String(localized: "Pinned")
        case .today:
            return String(localized: "Today")
        case .yesterday:
            return String(localized: "Yesterday")
        case .previous7Days:
            return String(localized: "Previous 7 days")
        case .previous30Days:
            return String(localized: "Previous 30 days")
        case .month(let year, let month):
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            let date = Calendar.current.date(from: components) ?? Date()
            return date.formatted(.dateTime.month(.wide).year())
        }
    }

    private var renameIsPresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var deleteIsPresented: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }
}
