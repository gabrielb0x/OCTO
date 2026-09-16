import OCTOCore
import SwiftUI

/// The ChatGPT accounts signed in on this device: which one is in use, how to switch, and how to
/// add another. Each account keeps its own chats, settings and subscription, in its own folder,
/// so switching never mixes two histories.
struct AccountsView: View {
    @Environment(AppModel.self) private var app
    @State private var isAddingAccount = false
    @State private var showDeviceCode = false
    @State private var switchingKey: String?
    @State private var accountToSignOut: StoredAccount?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(app.accounts) { account in
                    row(account)
                }
            } header: {
                Text("On this device")
            } footer: {
                Text("Each account keeps its own chats on this device. Switching doesn't touch what's in your ChatGPT accounts.")
            }

            Section {
                Button(action: addAccount) {
                    HStack {
                        Label("Add an account", systemImage: "person.badge.plus")
                        if isAddingAccount {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isAddingAccount || switchingKey != nil)
                Button {
                    showDeviceCode = true
                } label: {
                    Label("Add with a code", systemImage: "number")
                }
                .disabled(isAddingAccount || switchingKey != nil)
            } footer: {
                Text("Adding an account opens ChatGPT's sign-in page without the account you're already signed into, so you can choose another one. Signing in again to an account already here finds its chats where it left them.")
            }
            .foregroundStyle(Theme.primaryText)
        }
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDeviceCode) {
            DeviceCodeSheet()
        }
        .alert("Couldn't add the account", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Sign this account out?",
            isPresented: signOutIsPresented,
            titleVisibility: .visible,
            presenting: accountToSignOut
        ) { account in
            Button("Sign out", role: .destructive) {
                signOut(account)
            }
        } message: { account in
            Text("OCTO will forget \(title(account)) on this device and its session will be revoked. Its chats stay in your ChatGPT account.")
        }
    }

    // MARK: Rows

    private func row(_ account: StoredAccount) -> some View {
        let isCurrent = account.key == app.currentAccountKey
        return Button {
            switchTo(account)
        } label: {
            HStack(spacing: 12) {
                // Only the account in use has its picture downloaded; the others show their initial.
                AccountAvatar(name: account.name, email: account.email, image: isCurrent ? app.account.avatar : nil, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title(account))
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(verbatim: subtitle(account))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if switchingKey == account.key {
                    ProgressView()
                } else if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(app.settings.accentStyle.link)
                }
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isCurrent || switchingKey != nil || isAddingAccount)
        .swipeActions {
            Button(role: .destructive) {
                accountToSignOut = account
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        .contextMenu {
            if !isCurrent {
                Button {
                    switchTo(account)
                } label: {
                    Label("Switch to this account", systemImage: "arrow.left.arrow.right")
                }
            }
            Button(role: .destructive) {
                accountToSignOut = account
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    /// The name of an account, hidden behind dots like everywhere else when it is only an address
    /// and Privacy asks for it.
    private func title(_ account: StoredAccount) -> String {
        let name = account.displayName
        guard app.contactShield.isMasked, let email = account.email, name == email else { return name }
        return ContactMasking.email(email)
    }

    private func subtitle(_ account: StoredAccount) -> String {
        var parts: [String] = []
        if let email = account.email, !email.isEmpty, email != account.displayName {
            parts.append(app.contactShield.isMasked ? ContactMasking.email(email) : email)
        }
        if let plan = ChatGPTPlan.displayName(for: account.planType) {
            parts.append("ChatGPT \(plan)")
        }
        return parts.isEmpty ? String(localized: "ChatGPT account") : parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func switchTo(_ account: StoredAccount) {
        guard account.key != app.currentAccountKey, switchingKey == nil else { return }
        switchingKey = account.key
        Task {
            await app.switchAccount(to: account.key)
            switchingKey = nil
        }
    }

    private func addAccount() {
        guard !isAddingAccount else { return }
        isAddingAccount = true
        Task {
            defer { isAddingAccount = false }
            do {
                try await app.auth.signInWithChatGPT(addingAccount: true)
                await app.didSignIn()
            } catch AuthError.cancelled {
                // The sign-in sheet was closed.
            } catch {
                errorMessage = ChatSession.describe(error)
            }
        }
    }

    private func signOut(_ account: StoredAccount) {
        Task {
            await app.signOut(accountKey: account.key)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var signOutIsPresented: Binding<Bool> {
        Binding(get: { accountToSignOut != nil }, set: { if !$0 { accountToSignOut = nil } })
    }
}
