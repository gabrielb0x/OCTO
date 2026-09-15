import OCTOCore
import SwiftUI
import UIKit

/// A new version of OCTO: what changed, and ways to install it.
struct UpdateView: View {
    let release: AppRelease
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    if !release.notes.isEmpty {
                        MarkdownView(text: release.notes)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 44)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 10) {
                ForEach(Installer.available) { installer in
                    if let url = release.installURL(scheme: installer.scheme) {
                        Button {
                            openURL(url)
                        } label: {
                            Text("Install with \(installer.name)")
                                .font(.headline)
                                .foregroundStyle(Theme.onProminent)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.prominentFill)
                        .controlSize(.extraLarge)
                    }
                }
                if let ipaURL = release.ipaURL {
                    Button {
                        openURL(ipaURL)
                    } label: {
                        Label("Download the IPA", systemImage: "arrow.down.circle")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.extraLarge)
                }
                HStack(spacing: 10) {
                    Button {
                        openURL(release.pageURL)
                    } label: {
                        Text("View on GitHub")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        dismiss()
                    } label: {
                        Text("Later")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .presentationDetents([.large])
    }

    private var header: some View {
        VStack(spacing: 18) {
            ZStack(alignment: .topTrailing) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 50, height: 50)
                    .frame(width: 100, height: 100)
                    .glassEffect(.regular, in: .rect(cornerRadius: 30))
                Image(systemName: "arrow.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.tint(Theme.link.opacity(0.7)), in: .circle)
                    .offset(x: 14, y: -14)
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("OCTO \(release.version) is available")
                    .font(.largeTitle.bold())
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        var parts = [String(localized: "You have version \(AppInfo.version)")]
        if let date = release.publishedAt {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if let size = release.ipaSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }
}

/// Sideloading apps that install an IPA from a link.
struct Installer: Identifiable {
    let name: String
    let scheme: String

    var id: String { scheme }

    static let all = [
        Installer(name: "AltStore", scheme: "altstore"),
        Installer(name: "SideStore", scheme: "sidestore"),
    ]

    /// The installers on this device. iOS only answers for the schemes listed in the Info.plist.
    @MainActor
    static var available: [Installer] {
        all.filter { installer in
            URL(string: "\(installer.scheme)://").map { UIApplication.shared.canOpenURL($0) } ?? false
        }
    }
}

/// The update check in About: whether a newer version exists, and a button to look again.
struct UpdateStatusSection: View {
    @Environment(AppModel.self) private var app
    @State private var releaseToShow: AppRelease?

    var body: some View {
        Section {
            if let release = app.updates.available {
                Button {
                    releaseToShow = release
                } label: {
                    LabeledContent {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.tertiaryText)
                    } label: {
                        Label("OCTO \(release.version) is available", systemImage: "arrow.down.app.fill")
                    }
                }
                .foregroundStyle(Theme.primaryText)
            } else if app.updates.lastCheck != nil, app.updates.errorMessage == nil {
                Label("OCTO is up to date", systemImage: "checkmark.circle")
                    .foregroundStyle(Theme.secondaryText)
            }
            ActionRow(title: "Check for updates", systemImage: "arrow.triangle.2.circlepath") {
                await app.updates.check()
                if let release = app.updates.available {
                    releaseToShow = release
                } else if let error = app.updates.errorMessage {
                    app.toasts.show(error, style: .failure)
                } else {
                    app.toasts.show(String(localized: "OCTO is up to date"), style: .info)
                }
            }
            .foregroundStyle(Theme.primaryText)
        } header: {
            Text("Updates")
        } footer: {
            if let lastCheck = app.updates.lastCheck {
                Text("Last checked on GitHub \(lastCheck, style: .relative) ago.")
            } else {
                Text("OCTO looks for new versions on GitHub Releases.")
            }
        }
        .sheet(item: $releaseToShow) { release in
            UpdateView(release: release)
        }
    }
}
