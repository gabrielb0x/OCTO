import Foundation

/// The subscription of the ChatGPT account (`GET /accounts/check/v4-2023-04-27`).
public struct AccountSubscription: Codable, Equatable, Sendable {
    public enum Store: Equatable, Sendable {
        case web
        case appStore
        case googlePlay
    }

    public var planType: String?
    public var hasActiveSubscription: Bool
    /// End of the current period. ChatGPT keeps the dates of a subscription after it ended, so
    /// they only mean something while one is active: see `renewalDate` and `endDate`.
    public var expiresAt: Date?
    public var renewsAt: Date?
    public var cancelsAt: Date?
    public var willRenew: Bool?
    /// "monthly" or "yearly".
    public var billingPeriod: String?
    /// Where the subscription was bought, such as "chatgpt_web" or "chatgpt_mobile_ios".
    public var purchasePlatform: String?
    /// Name of the workspace for Business and Enterprise accounts.
    public var workspaceName: String?
    /// Feature flags of the account, shown in the developer tools.
    public var features: [String]

    public init(
        planType: String? = nil,
        hasActiveSubscription: Bool = false,
        expiresAt: Date? = nil,
        renewsAt: Date? = nil,
        cancelsAt: Date? = nil,
        willRenew: Bool? = nil,
        billingPeriod: String? = nil,
        purchasePlatform: String? = nil,
        workspaceName: String? = nil,
        features: [String] = []
    ) {
        self.planType = planType
        self.hasActiveSubscription = hasActiveSubscription
        self.expiresAt = expiresAt
        self.renewsAt = renewsAt
        self.cancelsAt = cancelsAt
        self.willRenew = willRenew
        self.billingPeriod = billingPeriod
        self.purchasePlatform = purchasePlatform
        self.workspaceName = workspaceName
        self.features = features
    }

    /// When the active subscription renews. Nil without a subscription, or once it was cancelled.
    public var renewalDate: Date? {
        guard hasActiveSubscription, !isCancelled else { return nil }
        return renewsAt ?? expiresAt
    }

    /// When an active subscription that won't renew stops.
    public var endDate: Date? {
        guard hasActiveSubscription, isCancelled else { return nil }
        return expiresAt ?? cancelsAt
    }

    private var isCancelled: Bool {
        willRenew == false || (cancelsAt != nil && renewsAt == nil)
    }

    public var store: Store? {
        switch purchasePlatform?.lowercased() {
        case "chatgpt_web"?, "web"?, "stripe"?: return .web
        case "chatgpt_mobile_ios"?, "ios"?, "apple"?, "app_store"?: return .appStore
        case "chatgpt_mobile_android"?, "android"?, "google"?, "google_play"?: return .googlePlay
        default: return nil
        }
    }

    /// Picks the account OCTO is signed in to (`accountID`), else the first one ChatGPT lists.
    public static func parse(_ data: Data, accountID: String?) -> AccountSubscription? {
        guard let object = JSONValue.object(data),
              let accounts = object["accounts"] as? [String: Any],
              !accounts.isEmpty
        else { return nil }
        let ordering = (object["account_ordering"] as? [Any])?.compactMap { JSONValue.string($0) } ?? []
        let candidates = [accountID].compactMap { $0 } + ordering + ["default"] + accounts.keys.sorted()
        guard let entry = candidates.lazy.compactMap({ accounts[$0] as? [String: Any] }).first else { return nil }

        let account = entry["account"] as? [String: Any] ?? [:]
        let entitlement = entry["entitlement"] as? [String: Any] ?? [:]
        let lastSubscription = entry["last_active_subscription"] as? [String: Any] ?? [:]
        let name = JSONValue.string(account["name"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isWorkspace = JSONValue.string(account["structure"]) == "workspace"
        return AccountSubscription(
            planType: JSONValue.string(account["plan_type"]),
            hasActiveSubscription: JSONValue.bool(entitlement["has_active_subscription"]) ?? false,
            expiresAt: FlexibleDate.parse(entitlement["expires_at"]),
            renewsAt: FlexibleDate.parse(entitlement["renews_at"]),
            cancelsAt: FlexibleDate.parse(entitlement["cancels_at"]),
            willRenew: JSONValue.bool(lastSubscription["will_renew"]),
            billingPeriod: JSONValue.string(entitlement["billing_period"]),
            purchasePlatform: JSONValue.string(lastSubscription["purchase_origin_platform"]),
            workspaceName: isWorkspace && name?.isEmpty == false ? name : nil,
            features: ((entry["features"] as? [Any])?.compactMap { JSONValue.string($0) } ?? []).sorted()
        )
    }
}
