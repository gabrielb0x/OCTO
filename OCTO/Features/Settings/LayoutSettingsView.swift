import OCTOCore
import SwiftUI

/// How OCTO is laid out: the sidebar of the ChatGPT app, or a tab bar at the bottom — and, with the
/// tab bar, which tabs it holds, in which order, and how it behaves. The chat list's own options
/// live here too.
struct LayoutSettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var settings = app.settings

        List {
            Section {
                LayoutPicker(selection: $settings.layout)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            } footer: {
                Text(settings.layout == .tabBar
                    ? LocalizedStringKey("Your chats, Home and Settings sit in a Liquid Glass bar at the bottom of the screen. Choose its tabs below.")
                    : LocalizedStringKey("Like the ChatGPT app: slide the chat aside, or tap the button at the top left, to see your chats."))
            }

            if settings.layout == .tabBar {
                tabSections
            }

            Section {
                Toggle(isOn: $settings.showsChatOrigin) {
                    Label("Where chats come from", systemImage: "tag")
                }
            } header: {
                Text("Chat list")
            } footer: {
                Text("ChatGPT's logo marks the chats of your ChatGPT account, and a terminal the chats written with Codex, which only exist on this device. The filter at the top of the list shows only one kind.")
            }
        }
        .navigationTitle("Layout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if settings.layout == .tabBar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: settings.layout)
    }

    @ViewBuilder
    private var tabSections: some View {
        @Bindable var settings = app.settings

        Section {
            ForEach(settings.tabBarTabs) { tab in
                tabRow(tab)
                    .deleteDisabled(tab == .home)
            }
            .onMove { source, destination in
                var tabs = settings.tabBarTabs
                tabs.move(fromOffsets: source, toOffset: destination)
                settings.setTabBarTabs(tabs)
            }
            .onDelete { offsets in
                var tabs = settings.tabBarTabs
                tabs.remove(atOffsets: offsets)
                settings.setTabBarTabs(tabs)
            }
        } header: {
            Text("In the tab bar")
        } footer: {
            Text("Swipe a tab to take it out of the bar, or tap Edit to change their order. Home always stays: it's where you write to ChatGPT.")
        }

        let others = AppTab.barTabs.filter { !settings.tabBarTabs.contains($0) }
        let isFull = settings.tabBarTabs.count >= AppTab.maximumInBar
        if !others.isEmpty {
            Section {
                ForEach(others) { tab in
                    Button {
                        withAnimation(.smooth(duration: 0.25)) {
                            settings.setTabBarTabs(settings.tabBarTabs + [tab])
                        }
                    } label: {
                        HStack(spacing: 12) {
                            tabRow(tab)
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(isFull ? Theme.tertiaryText : Theme.success)
                        }
                    }
                    .disabled(isFull)
                    .accessibilityHint(Text("Adds this tab to the bar"))
                }
            } header: {
                Text("More tabs")
            } footer: {
                if isFull {
                    Text("The bar holds up to 5 tabs. Take one out to add another.")
                }
            }
        }

        Section {
            Toggle(isOn: $settings.showsSearchTab) {
                Label("Search button", systemImage: "magnifyingglass")
            }
            Picker(selection: $settings.startTab) {
                ForEach(settings.visibleTabs) { tab in
                    Text(tab.title).tag(tab)
                }
            } label: {
                Label("Open on", systemImage: "arrow.up.forward.app")
            }
            Toggle(isOn: $settings.tabBarMinimizesOnScroll) {
                Label("Shrink while scrolling", systemImage: "arrow.down.right.and.arrow.up.left")
            }
        } footer: {
            Text("The search button sits apart, at the end of the bar, and looks through every chat — even inside the messages. While you scroll down a chat, the bar can shrink to leave it more room.")
        }
    }

    private func tabRow(_ tab: AppTab) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tab.systemImage)
                .font(.body)
                .foregroundStyle(Theme.primaryText)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .foregroundStyle(Theme.primaryText)
                Text(tab.summary)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

/// The two layouts side by side, each drawn as a small phone, like the appearance choice of iOS.
private struct LayoutPicker: View {
    @Environment(AppModel.self) private var app
    @Binding var selection: AppLayout

    var body: some View {
        HStack(spacing: 14) {
            ForEach(AppLayout.allCases) { layout in
                let isSelected = selection == layout
                Button {
                    withAnimation(.smooth(duration: 0.3)) {
                        selection = layout
                    }
                } label: {
                    VStack(spacing: 10) {
                        LayoutThumbnail(layout: layout, isSelected: isSelected, accent: app.settings.accentStyle.link)
                        Text(verbatim: layout.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.primaryText)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? app.settings.accentStyle.link : Theme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: layout.title))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 8)
        .sensoryFeedback(.selection, trigger: selection) { _, _ in
            app.settings.hapticsEnabled
        }
    }
}

/// A phone drawn in a few shapes: the chats in a drawer beside the conversation, or a conversation
/// above a glass tab bar and its round search button.
private struct LayoutThumbnail: View {
    let layout: AppLayout
    let isSelected: Bool
    let accent: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Theme.background)
            .overlay {
                sketch
                    .padding(.horizontal, 7)
                    .padding(.top, 14)
                    .padding(.bottom, 9)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? accent : Theme.separator, lineWidth: isSelected ? 2.5 : 1)
            }
            .frame(width: 100, height: 184)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var sketch: some View {
        switch layout {
        case .sidebar:
            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 6) {
                    Capsule()
                        .fill(Theme.surfaceElevated)
                        .frame(height: 10)
                    ForEach(0..<7, id: \.self) { index in
                        Capsule()
                            .fill(Theme.tertiaryText.opacity(0.55))
                            .frame(width: index.isMultiple(of: 3) ? 22 : 32, height: 4)
                    }
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(Theme.surfaceElevated)
                        .frame(height: 13)
                }
                .padding(5)
                .frame(width: 50)
                .background(Theme.sidebarBackground, in: .rect(cornerRadius: 11))
                conversation
            }
        case .tabBar:
            VStack(spacing: 6) {
                conversation
                HStack(spacing: 4) {
                    HStack(spacing: 9) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(index == 1 ? accent : Theme.tertiaryText)
                                .frame(width: 7, height: 7)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 19)
                    .background(Theme.surfaceElevated, in: .capsule)
                    Circle()
                        .fill(Theme.surfaceElevated)
                        .frame(width: 19, height: 19)
                        .overlay {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Theme.tertiaryText)
                        }
                }
            }
        }
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule()
                .fill(Theme.userBubble)
                .frame(width: 26, height: 10)
                .frame(maxWidth: .infinity, alignment: .trailing)
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(Theme.tertiaryText.opacity(0.45))
                    .frame(width: index == 4 ? 16 : 30, height: 3.5)
            }
            Spacer(minLength: 0)
            Capsule()
                .fill(Theme.surfaceElevated)
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
    }
}

extension AppLayout {
    var title: String {
        switch self {
        case .sidebar: return String(localized: "Sidebar")
        case .tabBar: return String(localized: "Tab bar")
        }
    }
}
