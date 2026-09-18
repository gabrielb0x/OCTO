import OCTOCore
import SwiftUI
import UIKit

/// Round Liquid Glass button with an SF Symbol, for icon-only controls outside toolbars.
struct GlassIconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text(label))
    }
}

/// Moving highlight used for "Thinking…" style status labels.
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(colors: [.clear, Theme.primaryText.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.5)
                            .offset(x: phase * proxy.size.width * 1.5)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

/// ChatGPT-style breathing dot shown while waiting for the first token.
struct PulsingDot: View {
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(Theme.primaryText)
            .frame(width: 13, height: 13)
            .scaleEffect(expanded ? 1 : 0.65)
            .opacity(expanded ? 1 : 0.7)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                    expanded = true
                }
            }
            .accessibilityLabel(Text("Generating a response"))
    }
}

/// The profile picture of the ChatGPT account, or the account's initial on a gradient.
struct AccountAvatar: View {
    let name: String?
    let email: String?
    let image: UIImage?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color(red: 0.36, green: 0.46, blue: 1.0), Color(red: 0.64, green: 0.38, blue: 0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(verbatim: initial)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initial: String {
        for source in [name, email] {
            if let letter = source?.first(where: { $0.isLetter || $0.isNumber }) {
                return String(letter).uppercased()
            }
        }
        return "C"
    }
}

/// "Upgrade" next to the chats button, the way the ChatGPT app offers it to accounts without a
/// subscription. It shows the plans, and Settings → Appearance can take it away.
/// The glass around it is the toolbar's own, like every other button up there. Compact, it's
/// only the sparkle, which leaves room for the model picker.
struct UpgradePill: View {
    var isCompact = false
    let action: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle")
                    .font(.system(size: isCompact ? 15 : 13, weight: .semibold))
                if !isCompact {
                    Text("Upgrade")
                        .font(.subheadline.weight(.semibold))
                }
            }
            .foregroundStyle(app.settings.accentStyle.link)
        }
        .accessibilityLabel(Text("Upgrade"))
        .accessibilityHint(Text("Shows the plans of ChatGPT and their prices"))
    }
}

/// A small mark telling where a chat comes from: ChatGPT's logo for the chats of the account,
/// Codex's terminal for the chats started in OCTO, which only exist on this device.
struct ChatOriginBadge: View {
    let origin: ChatOrigin

    var body: some View {
        Group {
            switch origin {
            case .chatGPT:
                Image("Logo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 13, height: 13)
            case .codex:
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundStyle(Theme.tertiaryText)
        .frame(width: 16)
        .accessibilityLabel(Text(origin.badgeTitle))
    }
}

extension ChatOrigin {
    /// What the mark next to a chat says to VoiceOver.
    var badgeTitle: LocalizedStringKey {
        switch self {
        case .chatGPT: return "From your ChatGPT account"
        case .codex: return "Written with Codex, on this device"
        }
    }
}

extension ChatOriginFilter {
    var title: LocalizedStringKey {
        switch self {
        case .all: return "All chats"
        case .chatGPT: return "ChatGPT"
        case .codex: return "Codex"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .all: return "From your account and from OCTO"
        case .chatGPT: return "The chats of your ChatGPT account"
        case .codex: return "Started in OCTO, kept on this device"
        }
    }
}

/// Chooses which chats the list shows: all of them, those of the ChatGPT account, or those
/// written with Codex in OCTO. The choice is kept.
struct ChatFilterMenu: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let current = app.settings.chatOriginFilter
        Menu {
            Section("Show") {
                ForEach(ChatOriginFilter.allCases) { filter in
                    Button {
                        app.settings.chatOriginFilter = filter
                    } label: {
                        if filter == current {
                            Label(filter.title, systemImage: "checkmark")
                        } else {
                            filterLabel(filter)
                        }
                        Text(filter.subtitle)
                    }
                }
            }
        } label: {
            Image(systemName: current == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .foregroundStyle(current == .all ? Theme.secondaryText : app.settings.accentStyle.link)
        }
        .menuOrder(.fixed)
        .accessibilityLabel(Text("Filter chats"))
    }

    @ViewBuilder
    private func filterLabel(_ filter: ChatOriginFilter) -> some View {
        switch filter {
        case .all: Label(filter.title, systemImage: "bubble.left.and.bubble.right")
        case .chatGPT: Label(filter.title, image: "Logo")
        case .codex: Label(filter.title, systemImage: "terminal")
        }
    }
}

/// A row of Settings holding something personal — the email address, the phone number — shown the
/// way Privacy asks: readable, behind dots until you tap them, hidden while the screen is
/// recorded, or never shown at all.
struct ContactRow: View {
    enum Kind {
        case email
        case phone
    }

    let title: LocalizedStringKey
    let systemImage: String
    let value: String
    let kind: Kind

    @Environment(AppModel.self) private var app
    @State private var isRevealed = false

    var body: some View {
        let shield = app.contactShield
        let isHidden = shield.isMasked && !isRevealed
        LabeledContent {
            HStack(spacing: 7) {
                Text(verbatim: isHidden ? masked : value)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if shield.canReveal {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .contentShape(.rect)
        .onTapGesture {
            guard shield.canReveal else { return }
            withAnimation(.smooth(duration: 0.2)) {
                isRevealed.toggle()
            }
        }
        .contextMenu {
            if shield.allowsCopy {
                Button {
                    Clipboard.copy(value, settings: app.settings, cleansLinks: false)
                    app.toasts.show(String(localized: "Copied"))
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
        // A revealed value goes back behind its dots on its own, and as soon as the screen is captured.
        .task(id: isRevealed) {
            guard isRevealed else { return }
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.2)) {
                isRevealed = false
            }
        }
        .onChange(of: app.protection.isScreenCaptured) { _, isCaptured in
            if isCaptured {
                isRevealed = false
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(shield.canReveal ? .isButton : [])
        .accessibilityHint(shield.canReveal ? Text(isRevealed ? LocalizedStringKey("Hides it again") : LocalizedStringKey("Shows it")) : Text(""))
    }

    private var masked: String {
        switch kind {
        case .email: return ContactMasking.email(value)
        case .phone: return ContactMasking.phone(value)
        }
    }
}

/// The label of a row that undoes something: signing out, deleting, turning off. iOS reddens the
/// text of a destructive button in a list but leaves its icon in the tint color; here the icon is
/// red too, as it is throughout the Settings app, and the text carries a little more weight so the
/// row reads as dangerous at a glance.
struct DestructiveLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.danger)
        } icon: {
            Image(systemName: systemImage)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.danger)
        }
    }
}

extension View {
    /// Lays a red tint over the row of a destructive action, on top of the usual row background,
    /// so the warning covers the whole row instead of just its words.
    func destructiveRow() -> some View {
        listRowBackground(
            ZStack {
                Color(uiColor: .secondarySystemGroupedBackground)
                Theme.dangerSurface
            }
        )
    }
}

/// A switch for one setting of the ChatGPT account, the way ChatGPT's own settings work: it shows
/// what the account has saved, changes it there right away, and comes back to where it was when
/// the account refuses. There is nothing to change until the account has said what it holds.
struct AccountSettingToggle: View {
    @Environment(AppModel.self) private var app
    let feature: AccountSettingFeature
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        let value = app.account.settings?[feature]
        let isSaving = app.account.savingSettings.contains(feature)
        return Toggle(isOn: Binding(get: { value ?? false }, set: change)) {
            HStack(spacing: 10) {
                Label(title, systemImage: systemImage)
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .disabled(value == nil || isSaving)
    }

    private func change(to value: Bool) {
        Task {
            do {
                try await app.account.setSetting(feature, to: value)
                app.toasts.show(value
                    ? String(localized: "Turned on in your ChatGPT account")
                    : String(localized: "Turned off in your ChatGPT account"))
            } catch let error where !error.isCancellation {
                app.toasts.show(ChatSession.describe(error), style: .failure)
            } catch {
                // Leaving the page cancels nothing: the account keeps what was sent.
            }
        }
    }
}

/// A settings page for something only the ChatGPT apps can do: what it is, and a way there.
struct ChatGPTOnlyPage: View {
    let title: LocalizedStringKey
    let systemImage: String
    let summary: LocalizedStringKey
    let details: LocalizedStringKey
    var link: URL = URL(string: "https://chatgpt.com/#settings")!
    var linkTitle: LocalizedStringKey = "Open ChatGPT settings"
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    Image(systemName: systemImage)
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Theme.primaryText)
                        .frame(width: 76, height: 76)
                        .glassEffect(.regular, in: .circle)
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Button {
                    openURL(link)
                } label: {
                    Label(linkTitle, systemImage: "arrow.up.right.square")
                }
                .foregroundStyle(Theme.primaryText)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// What Codex's catalog says about its models, in the language of the app when OCTO knows the
/// sentence: descriptions, speeds and their details come in English.
enum ModelText {
    static func localized(_ english: String) -> String {
        Bundle.main.localizedString(forKey: english, value: english, table: nil)
    }

    static func speedSystemImage(_ tier: String) -> String {
        switch tier {
        case "ultrafast": return "bolt"
        case "flex": return "tortoise"
        default: return "hare"
        }
    }
}

enum ReasoningEffortLabel {
    static func title(_ effort: String) -> String {
        switch effort {
        case "none": return String(localized: "Instant")
        case "minimal": return String(localized: "Minimal")
        case "low": return String(localized: "Light")
        case "medium": return String(localized: "Standard")
        case "high": return String(localized: "Extended")
        case "xhigh": return String(localized: "Heavy")
        case "max": return String(localized: "Max")
        case "ultra": return String(localized: "Ultra")
        case "persistent": return String(localized: "Persistent")
        default: return effort.capitalized
        }
    }

    static func systemImage(_ effort: String) -> String {
        switch ReasoningEffortScale.rank(effort) {
        case 0...1: return "hare"
        case 2: return "gauge.with.dots.needle.33percent"
        case 3: return "gauge.with.dots.needle.50percent"
        case 4: return "gauge.with.dots.needle.67percent"
        default: return "brain.head.profile"
        }
    }
}
