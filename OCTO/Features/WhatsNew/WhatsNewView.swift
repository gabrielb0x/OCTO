import SwiftUI

/// Presented once after an update, with what changed in the new version.
struct WhatsNewView: View {
    let notes: ReleaseNotes
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    header

                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(notes.changes) { change in
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: change.systemImage)
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(Theme.link)
                                    .frame(width: 44, height: 44)
                                    .glassEffect(.regular, in: .circle)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: change.title)
                                        .font(.headline)
                                        .foregroundStyle(Theme.primaryText)
                                    Text(verbatim: change.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 44)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button {
                dismiss()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(Theme.onProminent)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.prominentFill)
            .controlSize(.extraLarge)
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
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.tint(Theme.link.opacity(0.7)), in: .circle)
                    .offset(x: 14, y: -14)
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("What's new in OCTO")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Version \(notes.version)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
