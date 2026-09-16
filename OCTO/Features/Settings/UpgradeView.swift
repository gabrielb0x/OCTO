import OCTOCore
import SwiftUI

/// One line of the plan comparison: what it is, and whether a free account already has it.
private struct PlanFeature {
    let title: LocalizedStringKey
    let inFreePlan: Bool
}

/// A plan ChatGPT sells to one person, and what it adds over a free account — the comparison its
/// own paywall shows.
enum UpgradePlan: String, CaseIterable, Identifiable {
    case go
    case plus

    var id: String { rawValue }

    /// "Go", "Plus": the name ChatGPT gives the plan, the same in every language.
    var title: String { ChatGPTPlan.displayName(for: rawValue) ?? rawValue.capitalized }

    fileprivate var features: [PlanFeature] {
        switch self {
        case .go:
            [
                PlanFeature(title: "Base model", inFreePlan: true),
                PlanFeature(title: "Extended limits for messages and uploads", inFreePlan: false),
                PlanFeature(title: "Image creation", inFreePlan: false),
                PlanFeature(title: "Extended memory", inFreePlan: false),
            ]
        case .plus:
            [
                PlanFeature(title: "Base model", inFreePlan: true),
                PlanFeature(title: "Advanced models", inFreePlan: false),
                PlanFeature(title: "Extended limits for messages and uploads", inFreePlan: false),
                PlanFeature(title: "Advanced image creation with Thinking", inFreePlan: false),
                PlanFeature(title: "Extended memory", inFreePlan: false),
                PlanFeature(title: "Codex and Deep Research", inFreePlan: false),
                PlanFeature(title: "Early access to new features", inFreePlan: false),
            ]
        }
    }
}

/// The plans of ChatGPT, offered the way its own app offers them: the plan picker, what each one
/// adds to a free account, and the real price of the country the account is in, read from
/// ChatGPT's own pricing. OCTO sells nothing: the button opens ChatGPT, which takes the payment.
struct UpgradeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var plan: UpgradePlan = .plus

    private static let checkoutURL = URL(string: "https://chatgpt.com/#pricing")!

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                header
                if offeredPlans.count > 1 {
                    picker
                }
                comparison
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 22)
            .padding(.top, 48)
            .padding(.bottom, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) { checkoutBar }
        .background(Theme.background)
        .overlay(alignment: .topTrailing) {
            GlassIconButton(systemImage: "xmark", label: "Close") {
                dismiss()
            }
            .padding(.trailing, 16)
            .padding(.top, 10)
        }
        .presentationDetents([.large])
        .task {
            // Prices barely move, and the last ones are kept with the account.
            await app.account.refreshPricing(ifOlderThan: 6 * 3_600)
        }
    }

    // MARK: Plans

    private var pricing: CheckoutPricing? { app.account.pricing }

    /// Go isn't sold everywhere: a plan is offered when ChatGPT prices it where the account is,
    /// and Plus stays alone when OCTO couldn't read the prices at all.
    private var offeredPlans: [UpgradePlan] {
        guard let pricing else { return [.plus] }
        let offered = UpgradePlan.allCases.filter { pricing.plan($0.rawValue)?.monthly != nil }
        return offered.isEmpty ? [.plus] : offered
    }

    /// The plan the picker shows; Plus when the chosen one isn't sold here.
    private var selectedPlan: UpgradePlan {
        offeredPlans.contains(plan) ? plan : (offeredPlans.last ?? .plus)
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(app.settings.accentStyle.link)
                .accessibilityHidden(true)
            Text("Get ChatGPT \(selectedPlan.title)")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.primaryText)
            Text("Access advanced intelligent features")
                .font(.title3)
                .foregroundStyle(Theme.secondaryText)
        }
        .multilineTextAlignment(.center)
        .padding(.top, 10)
    }

    private var picker: some View {
        Picker("Plan", selection: $plan) {
            ForEach(offeredPlans) { plan in
                Text(verbatim: plan.title).tag(plan)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var comparison: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 20) {
            GridRow {
                Text("Features")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text(verbatim: "ChatGPT Free")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .gridColumnAlignment(.center)
                Text(verbatim: selectedPlan.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(app.settings.accentStyle.link)
                    .gridColumnAlignment(.center)
            }
            Divider()
                .gridCellUnsizedAxes(.horizontal)
            ForEach(Array(selectedPlan.features.enumerated()), id: \.offset) { _, feature in
                GridRow {
                    Text(feature.title)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                    mark(included: feature.inFreePlan, highlighted: false)
                    mark(included: true, highlighted: true)
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .animation(.smooth(duration: 0.25), value: selectedPlan)
    }

    private func mark(included: Bool, highlighted: Bool) -> some View {
        Image(systemName: included ? "checkmark" : "minus")
            .font(.system(size: included ? 17 : 15, weight: .semibold))
            .foregroundStyle(included ? (highlighted ? app.settings.accentStyle.link : Theme.secondaryText) : Theme.tertiaryText)
            .frame(width: 62)
            .gridColumnAlignment(.center)
            .accessibilityLabel(included ? Text("Included") : Text("Not included"))
    }

    private var checkoutBar: some View {
        VStack(spacing: 8) {
            Button {
                openURL(Self.checkoutURL)
            } label: {
                Text(verbatim: checkoutTitle)
                    .font(.headline)
                    .foregroundStyle(Theme.onProminent)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.prominentFill)
            .controlSize(.extraLarge)

            if let yearly = priceText(\.yearly) {
                Text("Or \(yearly) a month, billed yearly.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Text("Monthly auto-renewal. Cancel anytime.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Text("ChatGPT's own prices where you are. OCTO sells nothing: upgrading opens ChatGPT, which takes the payment.")
                .font(.caption2)
                .foregroundStyle(Theme.tertiaryText)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 4)
        // The plans scroll under the button: they fade out into the bar instead of showing
        // through the words below it.
        .background {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Theme.background.opacity(0), Theme.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 26)
                Theme.background
            }
            .padding(.top, -26)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: Prices

    private var checkoutTitle: String {
        guard let price = priceText(\.monthly) else { return String(localized: "Upgrade in ChatGPT") }
        return String(localized: "Upgrade for \(price)")
    }

    /// A price of the chosen plan, in the currency and the language of the device.
    private func priceText(_ period: KeyPath<CheckoutPricing.Plan, CheckoutPricing.Price?>) -> String? {
        guard let pricing, let price = pricing.plan(selectedPlan.rawValue)?[keyPath: period] else { return nil }
        return price.amount.formatted(.currency(code: pricing.currencyCode))
    }
}
