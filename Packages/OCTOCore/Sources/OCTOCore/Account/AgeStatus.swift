import Foundation

/// Where the account stands with ChatGPT's age checks (`GET /settings/is_adult`): treated as an
/// adult, kept in the under-18 experience, or verified.
public struct AgeStatus: Codable, Equatable, Sendable {
    public enum Standing: String, Codable, Sendable {
        /// An adult age was verified or confirmed with a date of birth.
        case verifiedAdult
        /// ChatGPT treats the account as an adult without asking for anything.
        case adult
        /// ChatGPT applies its under-18 experience, which only a verification lifts.
        case underEighteen
        case unknown
    }

    public var isAdult: Bool?
    /// `has_verified_age_or_dob`.
    public var hasVerifiedAge: Bool?
    public var isAgeKnown: Bool?
    /// `is_u18_model_policy_enabled`: the stricter rules for minors are on.
    public var underEighteenPolicyEnabled: Bool?
    /// `show_age_verification_setting`: ChatGPT offers the verification in its settings.
    public var offersVerification: Bool?
    /// Raw `age_status`, such as "under_18".
    public var status: String?

    public init(
        isAdult: Bool? = nil,
        hasVerifiedAge: Bool? = nil,
        isAgeKnown: Bool? = nil,
        underEighteenPolicyEnabled: Bool? = nil,
        offersVerification: Bool? = nil,
        status: String? = nil
    ) {
        self.isAdult = isAdult
        self.hasVerifiedAge = hasVerifiedAge
        self.isAgeKnown = isAgeKnown
        self.underEighteenPolicyEnabled = underEighteenPolicyEnabled
        self.offersVerification = offersVerification
        self.status = status
    }

    public var standing: Standing {
        let status = self.status?.lowercased() ?? ""
        if isAdult == false || ["under", "minor", "u18", "teen"].contains(where: status.contains) {
            return .underEighteen
        }
        if isAdult == true || status.contains("adult") {
            return hasVerifiedAge == true ? .verifiedAdult : .adult
        }
        return .unknown
    }

    public static func parse(_ data: Data) -> AgeStatus? {
        guard let object = JSONValue.object(data), object["is_adult"] != nil || object["age_status"] != nil else { return nil }
        return AgeStatus(
            isAdult: JSONValue.bool(object["is_adult"]),
            hasVerifiedAge: JSONValue.bool(object["has_verified_age_or_dob"]),
            isAgeKnown: JSONValue.bool(object["age_is_known"]),
            underEighteenPolicyEnabled: JSONValue.bool(object["is_u18_model_policy_enabled"]),
            offersVerification: JSONValue.bool(object["show_age_verification_setting"]),
            status: JSONValue.string(object["age_status"])
        )
    }
}
