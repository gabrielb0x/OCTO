import OCTOCore
import SwiftUI
import UIKit

/// The main screen, in one of two layouts. By default it's ChatGPT's: the chat slides aside to
/// reveal the sidebar underneath. Settings → Layout can put OCTO's screens in tabs instead, in a
/// Liquid Glass bar at the bottom.
struct MainView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: ChatSession
    @State private var isSidebarOpen = false
    @State private var isDragging = false
    /// True once a slide has been judged not to be a drawer one, until the finger lifts.
    @State private var dragRejected = false
    @State private var dragTranslation: CGFloat = 0
    @State private var showSettings = false
    /// The page Settings opens on, for the shortcuts that reach one directly.
    @State private var settingsPath: [SettingsRoute] = []
    /// The plans of ChatGPT, offered like in its app by "Upgrade" in the top bar.
    @State private var showUpgrade = false
    /// The tab on screen in the tab bar layout.
    @State private var selectedTab: AppTab
    /// The chats in a sheet, when the tab bar has no Chats tab.
    @State private var showsChatsSheet = false

    init(app: AppModel) {
        var initialSession: ChatSession?
        #if OCTO_DEMO
        if let scene = app.demoScene, [DemoScene.chat, .sidebar, .voice, .lightChat, .messageDetails, .tabs, .tabsChats, .scrollButton].contains(scene) {
            initialSession = app.makeSession(conversationID: DemoContent.featuredConversationID)
        }
        #endif
        _session = State(initialValue: initialSession ?? app.makeSession())
        _selectedTab = State(initialValue: app.settings.initialTab)
    }

    var body: some View {
        layout
            .sheet(isPresented: $showSettings) {
                #if OCTO_DEMO
                SettingsView(
                    initialPath: settingsPath.isEmpty ? DemoContent.settingsPath(for: app.demoScene) : settingsPath,
                    initialSection: DemoContent.settingsSection(for: app.demoScene)
                )
                #else
                SettingsView(initialPath: settingsPath)
                #endif
            }
            .sheet(isPresented: $showUpgrade) {
                UpgradeView()
            }
            .sheet(isPresented: $showsChatsSheet) {
                ChatsScreen(
                    selectedID: selectedChatID,
                    actions: chatListActions,
                    isSearchable: !app.settings.showsSearchTab,
                    onOpenSettings: settingsButtonAction,
                    onOpenAccounts: { openSettings(path: [.accounts]) },
                    onClose: { showsChatsSheet = false }
                )
            }
            .alert("Couldn't update your ChatGPT account", isPresented: syncErrorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(app.store.syncError ?? "")
            }
            .task {
                await app.refreshAccount()
                #if OCTO_DEMO
                await DemoContent.run(
                    app.demoScene,
                    app: app,
                    openSidebar: { setSidebar(open: true) },
                    openSettings: { showSettings = true },
                    openUpgrade: { showUpgrade = true }
                )
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await app.refreshAccount() }
                }
            }
            .onChange(of: app.notifications.conversationToOpen) { _, id in
                guard let id else { return }
                app.notifications.conversationToOpen = nil
                if id == session.id || app.store.summary(id: id) != nil || app.liveSession(for: id) != nil {
                    showSettings = false
                    open(id)
                }
            }
            // A tab taken out of the bar while on screen leaves for Home.
            .onChange(of: app.settings.visibleTabs) { _, tabs in
                if !tabs.contains(selectedTab) {
                    selectedTab = .home
                }
            }
            // Going back to the sidebar from the Settings tab keeps Settings on screen, as a sheet.
            .onChange(of: app.settings.layout) { old, new in
                if old == .tabBar, new == .sidebar, selectedTab == .settings {
                    openSettings(path: [.layout])
                }
            }
            .sensoryFeedback(.selection, trigger: isSidebarOpen) { _, _ in
                app.settings.hapticsEnabled
            }
    }

    @ViewBuilder
    private var layout: some View {
        switch app.settings.layout {
        case .sidebar:
            sidebarLayout
        case .tabBar:
            tabBarLayout
        }
    }

    private var syncErrorIsPresented: Binding<Bool> {
        Binding(get: { app.store.syncError != nil }, set: { if !$0 { app.store.syncError = nil } })
    }

    /// The chat highlighted in the lists: the one on screen, unless it's a temporary one.
    private var selectedChatID: UUID? {
        session.isTemporary ? nil : session.id
    }

    private var chatListActions: ChatListActions {
        ChatListActions(
            select: { id in
                open(id)
            },
            newChat: {
                startNewChat(temporary: app.settings.temporaryChatsByDefault)
                showHome()
            },
            newTemporaryChat: {
                startNewChat(temporary: true)
                showHome()
            },
            rename: rename,
            setPinned: setPinned,
            delete: delete
        )
    }

    // MARK: Sidebar layout

    private var sidebarLayout: some View {
        GeometryReader { proxy in
            let sidebarWidth = min(proxy.size.width * 0.84, 360)
            let progress = openProgress(sidebarWidth: sidebarWidth)

            ZStack(alignment: .leading) {
                SidebarView(
                    selectedID: selectedChatID,
                    actions: chatListActions,
                    onOpenSettings: { openSettings() },
                    onOpenAccounts: { openSettings(path: [.accounts]) }
                )
                .frame(width: sidebarWidth)
                .offset(x: -sidebarWidth * 0.3 * (1 - progress))
                .opacity(0.35 + 0.65 * progress)
                .simultaneousGesture(drawerGesture(sidebarWidth: sidebarWidth), including: isSidebarOpen ? .all : .subviews)

                chatView(showsChatsButton: true, onOpenChats: { setSidebar(open: true) })
                    .frame(width: proxy.size.width)
                    // Sliding right anywhere on the chat brings the chats out, as in the ChatGPT app.
                    .simultaneousGesture(drawerGesture(sidebarWidth: sidebarWidth))
                    .overlay {
                        if progress > 0.001 {
                            Color.black
                                .opacity(0.45 * progress)
                                .ignoresSafeArea()
                                .contentShape(Rectangle())
                                .onTapGesture { setSidebar(open: false) }
                                .gesture(drawerGesture(sidebarWidth: sidebarWidth))
                        }
                    }
                    // Masking with a shape that ignores the safe area keeps the chat drawing under the
                    // status bar and home indicator while still rounding its corners when it slides away.
                    .mask {
                        RoundedRectangle(cornerRadius: 34 * min(progress * 3, 1), style: .continuous)
                            .ignoresSafeArea()
                    }
                    .shadow(color: .black.opacity(0.55 * progress), radius: 30)
                    .offset(x: sidebarWidth * progress)
            }
        }
        .background(Theme.sidebarBackground.ignoresSafeArea())
    }

    private func chatView(showsChatsButton: Bool, onOpenChats: @escaping () -> Void) -> some View {
        ChatView(
            session: session,
            showsChatsButton: showsChatsButton,
            onOpenSidebar: onOpenChats,
            onNewChat: { startNewChat(temporary: app.settings.temporaryChatsByDefault) },
            onToggleTemporary: { startNewChat(temporary: !session.isTemporary) },
            onDelete: { delete(session.id) },
            onUpgrade: { showUpgrade = true }
        )
    }

    // MARK: Tab bar layout

    /// OCTO's screens as tabs of the system tab bar, which iOS draws in Liquid Glass. The search
    /// tab becomes the round button at the end of the bar.
    private var tabBarLayout: some View {
        TabView(selection: $selectedTab) {
            ForEach(app.settings.visibleTabs) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab, role: tab == .search ? TabRole.search : nil) {
                    tabContent(tab)
                }
            }
        }
        .tabBarMinimizeBehavior(app.settings.tabBarMinimizesOnScroll ? .onScrollDown : .never)
        .sensoryFeedback(.selection, trigger: selectedTab) { _, _ in
            app.settings.hapticsEnabled
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .home:
            // Without a Chats tab, the button that opens the chats shows them in a sheet.
            chatView(showsChatsButton: !app.settings.tabBarTabs.contains(.chats), onOpenChats: { showsChatsSheet = true })
        case .chats:
            ChatsScreen(
                selectedID: selectedChatID,
                actions: chatListActions,
                isSearchable: !app.settings.showsSearchTab,
                onOpenSettings: settingsButtonAction,
                onOpenAccounts: { openSettings(path: [.accounts]) }
            )
        case .projects:
            ProjectsScreen(selectedID: selectedChatID, actions: chatListActions)
        case .accounts:
            NavigationStack {
                AccountsView()
            }
        case .settings:
            #if OCTO_DEMO
            SettingsView(initialPath: DemoContent.settingsPath(for: app.demoScene), showsCloseButton: false)
            #else
            SettingsView(showsCloseButton: false)
            #endif
        case .search:
            SearchScreen(selectedID: selectedChatID, actions: chatListActions)
        }
    }

    /// Settings open from the chats when the bar has no Settings tab.
    private var settingsButtonAction: (() -> Void)? {
        guard app.settings.layout == .tabBar, !app.settings.tabBarTabs.contains(.settings) else { return nil }
        return { openSettings() }
    }

    // MARK: Navigation

    private func openSettings(path: [SettingsRoute] = []) {
        settingsPath = path
        showsChatsSheet = false
        showSettings = true
    }

    /// In the tab bar layout, a chat opened from a list shows in the Home tab.
    private func showHome() {
        showsChatsSheet = false
        if app.settings.layout == .tabBar {
            selectedTab = .home
        }
    }

    private func open(_ id: UUID) {
        if id != session.id {
            leaveCurrentSession()
            session = app.makeSession(conversationID: id)
        }
        setSidebar(open: false)
        showHome()
    }

    private func startNewChat(temporary: Bool) {
        if session.isBlank, session.isTemporary == temporary {
            setSidebar(open: false)
            return
        }
        leaveCurrentSession()
        session = app.makeSession(temporary: temporary)
        setSidebar(open: false)
    }

    /// The chat disappears right away; the confirmation shows once the account has deleted it too.
    private func delete(_ id: UUID) {
        if session.id == id {
            session.stop()
            session.discardIfTemporary()
            session = app.makeSession()
        }
        let app = app
        Task {
            do {
                try await app.store.delete(id: id)
                app.toasts.show(String(localized: "The chat has been deleted"))
            } catch {
                app.toasts.show(ChatSession.describe(error), style: .failure)
            }
        }
    }

    private func rename(_ id: UUID, to title: String) {
        if let live = liveSession(id) {
            live.rename(title)
        } else {
            app.store.rename(id: id, to: title)
        }
    }

    private func setPinned(_ id: UUID, _ isPinned: Bool) {
        if let live = liveSession(id) {
            live.setPinned(isPinned)
        } else {
            app.store.setPinned(isPinned, id: id)
        }
    }

    /// The open chat, or one still generating in the background, holds its own copy of the conversation.
    private func liveSession(_ id: UUID) -> ChatSession? {
        id == session.id ? session : app.liveSession(for: id)
    }

    private func leaveCurrentSession() {
        app.speech.stop()
        session.discardIfTemporary()
    }

    private func setSidebar(open: Bool) {
        if open {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        withAnimation(.snappy(duration: 0.34)) {
            isSidebarOpen = open
            dragTranslation = 0
        }
    }

    // MARK: Drawer gesture

    private func openProgress(sidebarWidth: CGFloat) -> CGFloat {
        let base: CGFloat = isSidebarOpen ? sidebarWidth : 0
        let offset = isDragging ? dragTranslation : 0
        return min(max((base + offset) / sidebarWidth, 0), 1)
    }

    private func drawerGesture(sidebarWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    // Decided once per slide: a sideways one moves the drawer, and everything else
                    // — scrolling the chat, a code block sliding under a finger — is left alone
                    // until the finger lifts.
                    guard !dragRejected else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.6, isSidebarOpen ? dx < 0 : dx > 0 else {
                        dragRejected = true
                        return
                    }
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    isDragging = true
                }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                dragRejected = false
                guard isDragging else { return }
                let projected = value.predictedEndTranslation.width
                let shouldOpen = isSidebarOpen ? projected > -sidebarWidth / 2 : projected > sidebarWidth / 2
                withAnimation(.snappy(duration: 0.34)) {
                    isDragging = false
                    dragTranslation = 0
                    isSidebarOpen = shouldOpen
                }
            }
    }
}
