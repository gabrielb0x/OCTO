import OCTOCore
import SwiftUI

/// The Chats tab of the tab bar layout — and the sheet standing in for it when it isn't in the
/// bar: shortcuts, projects and every chat by date, with the filter and a new chat button.
struct ChatsScreen: View {
    @Environment(AppModel.self) private var app
    let selectedID: UUID?
    let actions: ChatListActions
    /// The chats are searched here when the bar has no search button.
    var isSearchable = false
    /// Settings open from here when the bar has no Settings tab.
    var onOpenSettings: (() -> Void)?
    var onOpenAccounts: () -> Void = {}
    /// Set when the list is shown in a sheet, which then gets a close button.
    var onClose: (() -> Void)?

    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                ChatHistoryList(query: query, selectedID: selectedID, actions: actions)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.background.ignoresSafeArea())
            .detachedRefreshable {
                await app.store.syncWithAccount()
            }
            .navigationTitle("Chats")
            .toolbar {
                if let onOpenSettings {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onOpenSettings) {
                            AccountAvatar(name: app.account.profile?.name, email: app.accountEmail, image: app.account.avatar, size: 30)
                        }
                        .contextMenu {
                            AccountSwitchMenuItems(onOpenAccounts: onOpenAccounts, onOpenSettings: onOpenSettings)
                        }
                        .accessibilityLabel(Text("Settings"))
                        .accessibilityHint(Text("Hold to switch account"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ChatFilterMenu()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: actions.newChat) {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel(Text("New chat"))
                }
                if let onClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .close, action: onClose)
                    }
                }
            }
            .modifier(SearchableWhen(isOn: isSearchable, text: $query))
        }
    }
}

/// The search tab: the round glass button at the end of the tab bar. It looks through the chats
/// on this iPhone, then asks ChatGPT, which searches inside the messages of the whole account.
struct SearchScreen: View {
    let selectedID: UUID?
    let actions: ChatListActions

    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                        Text("Search your chats")
                            .font(.headline)
                        Text("OCTO looks through the chats on this iPhone, and ChatGPT inside the messages of your whole account.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 40)
                    .padding(.top, 120)
                    .frame(maxWidth: .infinity)
                } else {
                    ChatHistoryList(query: query, selectedID: selectedID, showsShortcuts: false, actions: actions)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 16)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Search")
            .searchable(text: $query, prompt: Text("Search chats"))
        }
    }
}

/// The Projects tab: the projects of the ChatGPT account, each opening on its chats.
struct ProjectsScreen: View {
    @Environment(AppModel.self) private var app
    let selectedID: UUID?
    let actions: ChatListActions

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if app.store.projects.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "folder")
                                .font(.title2)
                            Text("Your ChatGPT projects will appear here")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        ForEach(app.store.projects) { project in
                            NavigationLink(value: project.id) {
                                projectRow(project)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
            .background(Theme.background.ignoresSafeArea())
            .detachedRefreshable {
                await app.store.syncWithAccount()
            }
            .navigationTitle("Projects")
            .navigationDestination(for: String.self) { projectID in
                ScrollView {
                    ChatHistoryList(query: "", selectedID: selectedID, scope: .project(projectID), actions: actions)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 16)
                }
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle(projectName(projectID))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func projectRow(_ project: ChatProject) -> some View {
        HStack(spacing: 12) {
            ProjectIconView(project: project)
            Text(verbatim: project.name.isEmpty ? String(localized: "Project") : project.name)
                .font(.body.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(verbatim: "\(app.store.summaries(inProject: project.id).count)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.tertiaryText)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.tertiaryText)
        }
        .foregroundStyle(Theme.primaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(.rect(cornerRadius: 14))
    }

    private func projectName(_ id: String) -> String {
        guard let name = app.store.projects.first(where: { $0.id == id })?.name, !name.isEmpty else {
            return String(localized: "Project")
        }
        return name
    }
}

/// `searchable`, only when asked for.
private struct SearchableWhen: ViewModifier {
    let isOn: Bool
    @Binding var text: String

    @ViewBuilder
    func body(content: Content) -> some View {
        if isOn {
            content.searchable(text: $text, prompt: Text("Search chats"))
        } else {
            content
        }
    }
}

extension AppTab {
    var title: LocalizedStringKey {
        switch self {
        case .home: return "Home"
        case .chats: return "Chats"
        case .projects: return "Projects"
        case .accounts: return "Accounts"
        case .settings: return "Settings"
        case .search: return "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .chats: return "bubble.left.and.bubble.right"
        case .projects: return "folder"
        case .accounts: return "person.2"
        case .settings: return "gearshape"
        case .search: return "magnifyingglass"
        }
    }

    /// What the tab holds, for the tab bar settings.
    var summary: LocalizedStringKey {
        switch self {
        case .home: return "The chat you're writing in. Always in the bar."
        case .chats: return "Every chat, by date, with the filter."
        case .projects: return "The projects of your ChatGPT account."
        case .accounts: return "Switch between your accounts."
        case .settings: return "All of OCTO's settings."
        case .search: return "Search every chat, even inside the messages."
        }
    }
}
