import OCTOCore
import SwiftUI

/// What can be done to the chats of a list: the sidebar's, and the tabs of the tab bar layout.
struct ChatListActions {
    var select: (UUID) -> Void
    var newChat: () -> Void
    var newTemporaryChat: () -> Void
    var rename: (UUID, String) -> Void
    var setPinned: (UUID, Bool) -> Void
    var delete: (UUID) -> Void
}

/// History drawer modeled on the ChatGPT app: glass search field, shortcuts, projects, chats and account.
struct SidebarView: View {
    @Environment(AppModel.self) private var app
    let selectedID: UUID?
    let actions: ChatListActions
    let onOpenSettings: () -> Void
    let onOpenAccounts: () -> Void

    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                ChatHistoryList(query: query, selectedID: selectedID, actions: actions)
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
                    } else {
                        // Which chats the list shows sits at the end of the search field.
                        ChatFilterMenu()
                            .font(.body)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .glassEffect(.regular.interactive(), in: .capsule)

                GlassIconButton(systemImage: "square.and.pencil", label: "New chat", size: 44, action: actions.newChat)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
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
            AccountSwitchMenuItems(onOpenAccounts: onOpenAccounts, onOpenSettings: onOpenSettings)
        }
        .accessibilityLabel(Text("Settings"))
        .accessibilityHint(Text("Hold to switch account"))
    }
}

/// The accounts signed in on this device, to switch from one to another, then Accounts and Settings.
struct AccountSwitchMenuItems: View {
    @Environment(AppModel.self) private var app
    let onOpenAccounts: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ForEach(app.accounts) { account in
            Button {
                guard account.key != app.currentAccountKey else { return }
                Task { await app.switchAccount(to: account.key) }
            } label: {
                if account.key == app.currentAccountKey {
                    Label(title(account), systemImage: "checkmark")
                } else {
                    Text(verbatim: title(account))
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

    /// The name of an account in the switcher, behind dots when it is only an address and Privacy
    /// asks for it.
    private func title(_ account: StoredAccount) -> String {
        let name = account.displayName
        guard app.contactShield.isMasked, let email = account.email, name == email else { return name }
        return ContactMasking.email(email)
    }
}

/// The chats as the sidebar and the Chats tab list them: shortcuts, projects, then the chats by
/// date — or what's typed in the search field. Each chat can show where it comes from, and the
/// list only keeps the chats of the origin chosen in the filter.
struct ChatHistoryList: View {
    /// What the list holds: every chat, or the chats of one ChatGPT project.
    enum Scope: Equatable {
        case all
        case project(String)
    }

    @Environment(AppModel.self) private var app
    let query: String
    let selectedID: UUID?
    var scope: Scope = .all
    var showsShortcuts = true
    let actions: ChatListActions

    @State private var renameTarget: ConversationSummary?
    @State private var renameText = ""
    @State private var deleteTarget: ConversationSummary?
    @State private var expandedProjects: Set<String> = []

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 2) {
            switch scope {
            case .all:
                if isSearching {
                    searchResults
                } else {
                    if showsShortcuts {
                        shortcuts
                    }
                    syncStatus
                    filterStatus
                    projectsSection
                    chatsSection
                }
            case .project(let projectID):
                projectChats(projectID)
            }
        }
        // Also on appearing: the search tab builds the list once something is typed.
        .onChange(of: query, initial: true) { _, newValue in
            app.store.searchAccount(newValue)
        }
        .alert("Rename chat", isPresented: renameIsPresented) {
            TextField("Title", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let target = renameTarget {
                    actions.rename(target.id, renameText)
                }
            }
        }
        .confirmationDialog("Delete this chat?", isPresented: deleteIsPresented, titleVisibility: .visible, presenting: deleteTarget) { target in
            Button("Delete", role: .destructive) {
                actions.delete(target.id)
            }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var filter: ChatOriginFilter {
        app.settings.chatOriginFilter
    }

    // MARK: Sections

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 2) {
            shortcutRow(action: actions.newChat) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            } title: {
                Text(verbatim: "ChatGPT")
            }
            shortcutRow(action: actions.newTemporaryChat) {
                Image("TemporaryChat")
            } title: {
                Text("Temporary chat")
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 4)
    }

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

    /// Says which chats are left out, with a way to show them all again.
    @ViewBuilder
    private var filterStatus: some View {
        if filter != .all {
            HStack(spacing: 8) {
                filterIcon
                Text(filter == .chatGPT ? LocalizedStringKey("Only the chats of your ChatGPT account") : LocalizedStringKey("Only the chats written with Codex"))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Button("Show all") {
                    withAnimation(.smooth(duration: 0.25)) {
                        app.settings.chatOriginFilter = .all
                    }
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(app.settings.accentStyle.link)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.surface, in: .rect(cornerRadius: 14))
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var filterIcon: some View {
        switch filter {
        case .codex:
            ChatOriginBadge(origin: .codex)
        default:
            ChatOriginBadge(origin: .chatGPT)
        }
    }

    /// What's typed in the search field: first the chats already on this device, then those
    /// ChatGPT found in the account, which this iPhone has never downloaded.
    @ViewBuilder
    private var searchResults: some View {
        let local = filter.apply(to: app.store.search(query))
        // Codex chats have no copy in the account, so filtering them out leaves this set as it is.
        let known = Set(local.compactMap(\.remoteID))
        // Chats found in the account come from ChatGPT: the Codex filter leaves them out.
        let hits = filter == .codex ? [] : app.store.searchHits.filter { !known.contains($0.id) }
        if local.isEmpty, hits.isEmpty, !app.store.isSearchingAccount || filter == .codex {
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
            if app.store.isSearchingAccount, filter != .codex {
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

    /// Projects only hold chats of the ChatGPT account: the Codex filter hides them.
    @ViewBuilder
    private var projectsSection: some View {
        if !app.store.projects.isEmpty, filter != .codex {
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
        let sections = ConversationGrouping.sections(for: filter.apply(to: app.store.looseSummaries))
        if sections.isEmpty {
            if app.store.syncState == .syncing, filter != .codex {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            } else if filter == .codex {
                placeholder(title: "No chats written with Codex yet", systemImage: "terminal", detail: "The chats you start in OCTO are written with Codex and stay on this device.")
            } else if filter == .chatGPT {
                placeholder(title: "No chats from your ChatGPT account", systemImage: "bubble.left.and.bubble.right")
            } else if app.store.projects.isEmpty {
                placeholder(title: "Your chats will appear here", systemImage: "bubble.left.and.bubble.right")
            }
        }
        ForEach(sections) { section in
            sectionHeader(title(for: section.bucket))
            ForEach(section.conversations) { row($0) }
        }
        // Older chats of the account load as the list reaches its end; Codex chats are all here.
        if app.store.canLoadMore, filter != .codex {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .task(id: app.store.summaries.count) {
                    await app.store.loadMoreFromAccount()
                }
        }
    }

    @ViewBuilder
    private func projectChats(_ projectID: String) -> some View {
        let chats = app.store.summaries(inProject: projectID)
        if chats.isEmpty {
            placeholder(title: "No chats in this project", systemImage: "folder")
        } else {
            ForEach(chats) { row($0) }
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
                ProjectIconView(project: project)
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
            actions.select(summary.id)
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
                if app.settings.showsChatOrigin {
                    ChatOriginBadge(origin: summary.origin)
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
            Section(summary.origin == .chatGPT ? LocalizedStringKey("From your ChatGPT account") : LocalizedStringKey("Written with Codex, on this device")) {
                Button {
                    actions.setPinned(summary.id, !summary.isPinned)
                } label: {
                    Label(summary.isPinned ? LocalizedStringKey("Unpin") : LocalizedStringKey("Pin"), systemImage: summary.isPinned ? "pin.slash" : "pin")
                }
                Button {
                    renameText = summary.title
                    renameTarget = summary
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
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
            actions.select(app.store.adopt(hit.summary))
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

    private func placeholder(title: LocalizedStringKey, systemImage: String, detail: LocalizedStringKey? = nil) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
            Text(title)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(Theme.tertiaryText)
        .padding(.horizontal, 24)
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

/// The icon of a ChatGPT project, in its color.
struct ProjectIconView: View {
    let project: ChatProject

    var body: some View {
        Image(systemName: ProjectIcon.systemImage(for: project.iconName))
            .font(.body)
            .foregroundStyle(project.colorHex.flatMap { Color(hex: $0) } ?? Theme.primaryText)
            .frame(width: 26, height: 26)
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
