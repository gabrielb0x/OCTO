import OCTOCore
import PhotosUI
import SwiftUI
import UIKit

/// ChatGPT's "Edit profile": the photo, the display name and the username people see of you,
/// saved to the ChatGPT account the way its own apps save them.
struct EditProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var username = ""
    /// What the account holds, to send only what changed.
    @State private var savedDisplayName = ""
    @State private var savedUsername = ""
    /// A photo picked but not saved yet, ready to upload.
    @State private var photoData: Data?
    @State private var photoSelection: PhotosPickerItem?
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case displayName
        case username
    }

    private var normalizedDisplayName: String {
        SocialProfileAPI.normalizedDisplayName(displayName)
    }

    private var normalizedUsername: String {
        SocialProfileAPI.normalizedUsername(username)
    }

    private var hasChanges: Bool {
        photoData != nil || normalizedDisplayName != savedDisplayName || normalizedUsername != savedUsername
    }

    /// Like ChatGPT, a profile always keeps a name and a username.
    private var canSave: Bool {
        hasChanges && !isSaving && !normalizedDisplayName.isEmpty && !normalizedUsername.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    photoMenu
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Display name", text: $displayName)
                        .textContentType(.name)
                        .submitLabel(.next)
                        .focused($focusedField, equals: .displayName)
                        .onSubmit { focusedField = .username }
                } header: {
                    Text("Display name")
                }

                Section {
                    HStack(spacing: 1) {
                        Text(verbatim: "@")
                            .foregroundStyle(Theme.secondaryText)
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($focusedField, equals: .username)
                            .onSubmit(save)
                    }
                } header: {
                    Text("Username")
                } footer: {
                    Text("Your photo, name and username are the profile people see of you in ChatGPT, such as in group chats. They're saved in your ChatGPT account.")
                }

                if let errorMessage {
                    Section {
                        Label {
                            Text(verbatim: errorMessage)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.warning)
                        }
                        .font(.subheadline)
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.onProminent)
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.prominentFill)
                    .disabled(!canSave)
                    .accessibilityLabel(Text("Save"))
                }
            }
            .photosPicker(isPresented: $showsPhotoPicker, selection: $photoSelection, matching: .images)
            .onChange(of: photoSelection) { _, item in
                loadPhoto(item)
            }
            .fullScreenCover(isPresented: $showsCamera) {
                CameraPicker { image in
                    usePhoto(image)
                }
                .ignoresSafeArea()
            }
            // Changes aren't lost to a slide down: the close button leaves on purpose.
            .interactiveDismissDisabled(hasChanges || isSaving)
            .task {
                await load()
            }
        }
    }

    // MARK: Photo

    private var photoMenu: some View {
        Menu {
            Button {
                showsPhotoPicker = true
            } label: {
                Label("Choose a photo", systemImage: "photo.on.rectangle.angled")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showsCamera = true
                } label: {
                    Label("Take a photo", systemImage: "camera")
                }
            }
        } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 112, height: 112)
                            .clipShape(Circle())
                    } else {
                        AccountAvatar(name: app.accountName, email: app.accountEmail, image: app.account.avatar, size: 112)
                    }
                }
                .overlay {
                    if isLoading {
                        ProgressView()
                            .controlSize(.large)
                    }
                }
                Image(systemName: "camera.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .offset(x: 4, y: 4)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Change profile photo"))
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        photoSelection = nil
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                errorMessage = String(localized: "This photo couldn't be opened.")
                return
            }
            usePhoto(image)
        }
    }

    private func usePhoto(_ image: UIImage) {
        guard let data = ImageProcessing.profilePhoto(from: image) else {
            errorMessage = String(localized: "This photo couldn't be opened.")
            return
        }
        photoData = data
        errorMessage = nil
    }

    // MARK: Saving

    /// Fills the fields with the profile OCTO knows, then with the one ChatGPT has now.
    private func load() async {
        fill(overwritingEdits: true)
        isLoading = true
        await app.account.refreshSocialProfile()
        isLoading = false
        fill(overwritingEdits: false)
    }

    private func fill(overwritingEdits: Bool) {
        let name = app.account.displayName ?? ""
        let handle = app.account.socialProfile?.username ?? ""
        if overwritingEdits || normalizedDisplayName == savedDisplayName {
            displayName = name
        }
        if overwritingEdits || normalizedUsername == savedUsername {
            username = handle
        }
        savedDisplayName = name
        savedUsername = handle
    }

    /// The photo first, then the username and the name, in the order of ChatGPT's own screen.
    /// What was saved stays saved when a later step fails, so trying again only sends the rest.
    private func save() {
        guard canSave else { return }
        focusedField = nil
        isSaving = true
        errorMessage = nil
        let name = normalizedDisplayName
        let handle = normalizedUsername
        Task {
            do {
                if let photoData {
                    try await app.account.setProfilePhoto(photoData)
                    self.photoData = nil
                }
                if handle != savedUsername {
                    try await app.account.setUsername(handle)
                    savedUsername = handle
                }
                if name != savedDisplayName {
                    try await app.account.setDisplayName(name)
                    savedDisplayName = name
                }
                app.toasts.show(String(localized: "Your profile has been updated"))
                dismiss()
            } catch let error where !error.isCancellation {
                errorMessage = ChatSession.describe(error)
            } catch {
                // Closing the sheet mid-way leaves what was already saved.
            }
            isSaving = false
        }
    }
}
