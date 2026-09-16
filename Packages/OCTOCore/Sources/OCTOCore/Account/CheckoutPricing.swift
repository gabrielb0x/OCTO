import Foundation

/// What ChatGPT charges for its plans in one country
/// (`GET /backend-api/checkout_pricing_config/configs/{country}`), the call its website makes
/// before showing the plans. OCTO reads it so the Upgrade screen shows the real price of the
/// country the account is in; subscribing still happens in ChatGPT.
public struct CheckoutPricing: Codable, Equatable, Sendable {
    /// What a plan costs over one billing period.
    public struct Price: Codable, Equatable, Sendable {
        public var amount: Double
        /// True when the amount already includes VAT, the way ChatGPT shows prices in Europe.
        public var includesTax: Bool

        public init(amount: Double, includesTax: Bool = true) {
            self.amount = amount
            self.includesTax = includesTax
        }
    }

    public struct Plan: Codable, Equatable, Sendable, Identifiable {
        /// Raw plan key such as "go", "plus" or "pro".
        public var key: String
        public var monthly: Price?
        /// What a month costs when paying for a year, for the plans that offer it.
        public var yearly: Price?

        public var id: String { key }

        public init(key: String, monthly: Price? = nil, yearly: Price? = nil) {
            self.key = key
            self.monthly = monthly
            self.yearly = yearly
        }
    }

    public var countryCode: String
    /// ISO currency code such as "EUR", to format the amounts in the language of the device.
    public var currencyCode: String
    /// The VAT rate applied to the amounts, when the country has one.
    public var taxPercent: Double?
    public var plans: [Plan]

    public init(countryCode: String, currencyCode: String, taxPercent: Double? = nil, plans: [Plan] = []) {
        self.countryCode = countryCode
        self.currencyCode = currencyCode
        self.taxPercent = taxPercent
        self.plans = plans
    }

    /// The plans someone subscribes to for themselves, cheapest first, as ChatGPT offers them.
    public static let personalPlanKeys = ["go", "plus", "pro"]

    public var personalPlans: [Plan] {
        Self.personalPlanKeys.compactMap { plan($0) }
    }

    public func plan(_ key: String) -> Plan? {
        plans.first { $0.key == key }
    }

    /// The two-letter country of the pricing address. Only a real region code is used: anything
    /// else asks for the prices ChatGPT shows in the United States, rather than keeping whatever
    /// letters it holds and inventing a country out of them.
    public static func countryCode(for region: String?) -> String {
        let value = (region ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isRegionCode = value.count == 2 && value.allSatisfy { $0.isASCII && $0.isLetter }
        return isRegionCode ? value : "US"
    }

    public static func parse(_ data: Data) -> CheckoutPricing? {
        guard let object = JSONValue.object(data),
              let config = object["currency_config"] as? [String: Any]
        else { return nil }

        var plans: [Plan] = []
        for (key, value) in config {
            guard let entry = value as? [String: Any] else { continue }
            let monthly = price(entry["month"])
            let yearly = price(entry["year"])
            // The free plan is priced at zero, and the currency and tax keys aren't plans at all.
            guard monthly != nil || yearly != nil else { continue }
            plans.append(Plan(key: key, monthly: monthly, yearly: yearly))
        }
        guard !plans.isEmpty else { return nil }

        return CheckoutPricing(
            countryCode: JSONValue.string(object["country_code"]) ?? "",
            currencyCode: JSONValue.string(config["symbol_code"]) ?? "USD",
            taxPercent: JSONValue.double(config["tax_percent"]),
            plans: plans.sorted { ($0.monthly?.amount ?? .greatestFiniteMagnitude, $0.key) < ($1.monthly?.amount ?? .greatestFiniteMagnitude, $1.key) }
        )
    }

    /// One `{"amount": 23.0, "tax": "inclusive"}` entry. The `psp_override` next to it is the
    /// price without VAT, which ChatGPT only uses at checkout, so it's left alone here.
    static func price(_ value: Any?) -> Price? {
        guard let entry = value as? [String: Any],
              let amount = JSONValue.double(entry["amount"]), amount > 0
        else { return nil }
        return Price(amount: amount, includesTax: JSONValue.string(entry["tax"]) != "exclusive")
    }
}
