import OCTOCore
import SwiftUI
import UIKit

/// ChatGPT-style layout: the chat slides aside to reveal the sidebar underneath.
struct MainView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @State private var session: ChatSession
    @State private var isSidebarOpen = false
    @State private var isDragging = false
    @State private var dragTranslation: CGFloat = 0
    @State private var showSettings = false

    init(app: AppModel) {
        var initialSession: ChatSession?
        #if OCTO_DEMO
        if let scene = app.demoScene, [DemoScene.chat, .sidebar, .voice, .lightChat, .messageDetails].contains(scene) {
            initialSession = app.makeSession(conversationID: DemoContent.featuredConversationID)
        }
        #endif
        _session = State(initialValue: initialSession ?? app.makeSession())
    }

    var body: some View {
        GeometryReader { proxy in
            let sidebarWidth = min(proxy.size.width * 0.84, 360)
            let progress = openProgress(sidebarWidth: sidebarWidth)

            ZStack(alignment: .leading) {
                SidebarView(
                    selectedID: session.isTemporary ? nil : session.id,
                    onSelect: open,
                    onNewChat: { startNewChat(temporary: app.settings.temporaryChatsByDefault) },
                    onNewTemporaryChat: { startNewChat(temporary: true) },
                    onRename: rename,
                    onSetPinned: setPinned,
                    onDelete: delete,
                    onOpenSettings: { showSettings = true }
                )
                .frame(width: sidebarWidth)
                .offset(x: -sidebarWidth * 0.3 * (1 - progress))
                .opacity(0.35 + 0.65 * progress)
                .simultaneousGesture(drawerGesture(sidebarWidth: sidebarWidth), including: isSidebarOpen ? .all : .subviews)

                ChatView(
                    session: session,
                    onOpenSidebar: { setSidebar(open: true) },
                    onNewChat: { startNewChat(temporary: app.settings.temporaryChatsByDefault) },
                    onToggleTemporary: { startNewChat(temporary: !session.isTemporary) },
                    onDelete: { delete(session.id) }
                )
                .frame(width: proxy.size.width)
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
                .overlay(alignment: .leading) {
                    if !isSidebarOpen {
                        Color.clear
                            .frame(width: 20)
                            .contentShape(Rectangle())
                            .gesture(drawerGesture(sidebarWidth: sidebarWidth))
                            .padding(.top, 60)
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
        .sheet(isPresented: $showSettings) {
            #if OCTO_DEMO
            SettingsView(initialPath: DemoContent.settingsPath(for: app.demoScene), initialSection: DemoContent.settingsSection(for: app.demoScene))
            #else
            SettingsView()
            #endif
        }
        .alert("Couldn't update your ChatGPT account", isPresented: syncErrorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.store.syncError ?? "")
        }
        .task {
            await app.refreshAccount()
            #if OCTO_DEMO
            await DemoContent.run(app.demoScene, app: app, openSidebar: { setSidebar(open: true) }, openSettings: { showSettings = true })
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
        .sensoryFeedback(.selection, trigger: isSidebarOpen) { _, _ in
            app.settings.hapticsEnabled
        }
    }

    private var syncErrorIsPresented: Binding<Bool> {
        Binding(get: { app.store.syncError != nil }, set: { if !$0 { app.store.syncError = nil } })
    }

    // MARK: Navigation

    private func open(_ id: UUID) {
        if id != session.id {
            leaveCurrentSession()
            session = app.makeSession(conversationID: id)
        }
        setSidebar(open: false)
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
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if !isDragging {
                    guard abs(dx) > abs(dy) * 1.6, isSidebarOpen ? dx < 0 : dx > 0 else { return }
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    isDragging = true
                }
                dragTranslation = dx
            }
            .onEnded { value in
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
