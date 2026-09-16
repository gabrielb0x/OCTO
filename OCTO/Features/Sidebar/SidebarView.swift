import OCTOCore
import SwiftUI

/// History drawer modeled on the ChatGPT app: glass search field, shortcuts, projects, chats and account.
struct SidebarView: View {
    @Environment(AppModel.self) private var app
    let selectedID: UUID?
    let onSelect: (UUID) -> Void
    let onNewChat: () -> Void
    let onNewTemporaryChat: () -> Void
    let onRename: (UUID, String) -> Void
    let onSetPinned: (UUID, Bool) -> Void
    let onDelete: (UUID) -> Void
    let onOpenSettings: () -> Void
    let onOpenAccounts: () -> Void

    @State private var query = ""
    @State private var renameTarget: ConversationSummary?
    @State private var renameText = ""
    @State private var deleteTarget: ConversationSummary?
    @State private var expandedProjects: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if isSearching {
                        searchResults
                    } else {
                        shortcuts
                        syncStatus
                        projectsSection
                        chatsSection
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.immediately)
            .detachedRefreshable {
                await app.store.syncWithAccount()
            }

            footer
        }
        .background(Theme.sidebarBackground.ignoresSafeArea())
        .onChange(of: query) { _, newValue in
            app.store.searchAccount(newValue)
        }
        .alert("Rename chat", isPresented: renameIsPresented) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let target = renameTarget {
                    onRename(target.id, renameText)
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
                    TextField("Search", text: $query)
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
                .frame(height: 44)
                .glassEffect(.regular.interactive(), in: .capsule)

                GlassIconButton(systemImage: "square.and.pencil", label: "New chat", size: 44, action: onNewChat)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 2) {
            shortcutRow(action: onNewChat) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            } title: {
                Text(verbatim: "ChatGPT")
            }
            shortcutRow(action: onNewTemporaryChat) {
                Image("TemporaryChat")
            } title: {
                Text("Temporary chat")
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        Button(action: onOpenSettings) {
            HStack(spacing: 12) {
                AccountAvatar(name: app.account.profile?.name, email: app.accountEmail, image: app.account.avatar, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: app.shieldedAccountName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(verbatim: app.planName)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "gearshape")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                    .overlay(alignment: .topTrailing) {
                        // A new version waits in Settings.
                        if app.updates.available != nil {
                            Circle()
                                .fill(Theme.danger)
                                .frame(width: 8, height: 8)
                                .offset(x: 3, y: -2)
                        }
                    }
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        // Holding the account switches between the accounts signed in, without going through Settings.
        .contextMenu {
            ForEach(app.accounts) { account in
                Button {
                    guard account.key != app.currentAccountKey else { return }
                    Task { await app.switchAccount(to: account.key) }
                } label: {
                    if account.key == app.currentAccountKey {
                        Label(accountTitle(account), systemImage: "checkmark")
                    } else {
                        Text(verbatim: accountTitle(account))
                    }
                }
            }
            Divider()
            Button(action: onOpenAccounts) {
                Label("Accounts", systemImage: "person.2")
            }
            Button(action: onOpenSettings) {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .accessibilityLabel(Text("Settings"))
        .accessibilityHint(Text("Hold to switch account"))
    }

    /// The name of an account in the switcher, behind dots when it is only an address and Privacy
    /// asks for it.
    private func accountTitle(_ account: StoredAccount) -> String {
        let name = account.displayName
        guard app.contactShield.isMasked, let email = account.email, name == email else { return name }
        return ContactMasking.email(email)
    }

    // MARK: Sections

    @ViewBuilder
    private var syncStatus: some View {
        if case .failed(let message) = app.store.syncState {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't load your ChatGPT chats")
                        .font(.subheadline.weight(.semibold))
                    Text(verbatim: message)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Button("Try again") {
                        Task { await app.store.syncWithAccount() }
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.primaryText)
            .padding(12)
            .background(Theme.surface, in: .rect(cornerRadius: 16))
            .padding(.vertical, 6)
        }
    }

    /// What's typed in the search field: first the chats already on this device, then those
    /// ChatGPT found in the account, which this iPhone has never downloaded.
    @ViewBuilder
    private var searchResults: some View {
        let local = app.store.search(query)
        let known = Set(local.compactMap(\.remoteID))
        let hits = app.store.searchHits.filter { !known.contains($0.id) }
        if local.isEmpty, hits.isEmpty, !app.store.isSearchingAccount {
            placeholder(title: "No results", systemImage: "magnifyingglass")
        } else {
            if !local.isEmpty {
                sectionHeader(hits.isEmpty ? String(localized: "Results") : String(localized: "On this device"))
                ForEach(local) { row($0) }
            }
            if !hits.isEmpty {
                sectionHeader(String(localized: "In your ChatGPT account"))
                ForEach(hits) { hitRow($0) }
            }
            if app.store.isSearchingAccount {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching your account…")
                        .font(.footnote)
                        .foregroundStyle(Theme.tertiaryText)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private var projectsSection: some View {
        if !app.store.projects.isEmpty {
            sectionHeader(String(localized: "Projects"))
            ForEach(app.store.projects) { project in
                projectRow(project)
                if expandedProjects.contains(project.id) {
                    let chats = app.store.summaries(inProject: project.id)
                    if chats.isEmpty {
                        Text("No chats in this project")
                            .font(.subheadline)
                            .foregroundStyle(Theme.tertiaryText)
                            .padding(.leading, 50)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(chats) { row($0, indented: true) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var chatsSection: some View {
        let sections = ConversationGrouping.sections(for: app.store.looseSummaries)
        if sections.isEmpty {
            if app.store.syncState == .syncing {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else if app.store.projects.isEmpty {
                placeholder(title: "Your chats will appear here", systemImage: "bubble.left.and.bubble.right")
            }
        }
        ForEach(sections) { section in
            sectionHeader(title(for: section.bucket))
            ForEach(section.conversations) { row($0) }
        }
        if app.store.canLoadMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .task(id: app.store.summaries.count) {
                    await app.store.loadMoreFromAccount()
                }
        }
    }

    // MARK: Rows

    private func shortcutRow<Icon: View, Title: View>(
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder title: () -> Title
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon()
                    .frame(width: 26, height: 26)
                title()
                    .font(.body.weight(.medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func projectRow(_ project: ChatProject) -> some View {
        let isExpanded = expandedProjects.contains(project.id)
        return Button {
            withAnimation(.smooth(duration: 0.25)) {
                if isExpanded {
                    expandedProjects.remove(project.id)
                } else {
                    expandedProjects.insert(project.id)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: ProjectIcon.systemImage(for: project.iconName))
                    .font(.body)
                    .foregroundStyle(project.colorHex.flatMap { Color(hex: $0) } ?? Theme.primaryText)
                    .frame(width: 26, height: 26)
                Text(verbatim: project.name.isEmpty ? String(localized: "Project") : project.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.tertiaryText)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func row(_ summary: ConversationSummary, indented: Bool = false) -> some View {
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
            .padding(.leading, indented ? 50 : 12)
            .padding(.trailing, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.selection : Color.clear, in: .rect(cornerRadius: 14))
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onSetPinned(summary.id, !summary.isPinned)
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

    /// A chat ChatGPT found in the account, with the passage that matched. Opening it puts the chat
    /// in the history and downloads its messages.
    private func hitRow(_ hit: RemoteSearchHit) -> some View {
        Button {
            onSelect(app.store.adopt(hit.summary))
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.footnote)
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.top, 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: hit.title.isEmpty ? String(localized: "New chat") : hit.title)
                        .font(.body)
                        .lineLimit(1)
                        .foregroundStyle(Theme.primaryText)
                    if let snippet = hit.snippet {
                        Text(verbatim: snippet)
                            .font(.caption)
                            .lineLimit(2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
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

/// SF Symbol for the icon of a ChatGPT project.
enum ProjectIcon {
    static func systemImage(for name: String?) -> String {
        switch name?.lowercased() {
        case "graduation-cap"?: return "graduationcap"
        case "book"?, "book-open"?: return "book"
        case "code"?, "terminal"?: return "chevron.left.forwardslash.chevron.right"
        case "briefcase"?: return "briefcase"
        case "heart"?: return "heart"
        case "star"?: return "star"
        case "flask"?, "beaker"?: return "flask"
        case "music"?: return "music.note"
        case "camera"?: return "camera"
        case "globe"?: return "globe"
        case "pencil"?, "pen"?: return "pencil"
        case "lightbulb"?: return "lightbulb"
        case "dollar"?, "money"?: return "dollarsign"
        case "plane"?, "airplane"?: return "airplane"
        case "house"?, "home"?: return "house"
        case "chart"?, "chart-bar"?: return "chart.bar"
        case "palette"?, "paint"?: return "paintpalette"
        case "gamepad"?, "game"?: return "gamecontroller"
        default: return "folder"
        }
    }
}
