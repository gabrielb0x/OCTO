import Foundation
import Testing
@testable import OCTOCore

@Suite struct AccountKeyTests {
    @Test func keepsChatGPTIdentifiersAsTheyAre() {
        // The identifiers ChatGPT hands out already fit in a path and a keychain item.
        #expect(AccountKey.make(userID: "user-jVx2J6OrAoaK6OEsnCk8PyYy") == "user-jVx2J6OrAoaK6OEsnCk8PyYy")
        // Case is kept, so two accounts differing only by case stay apart.
        #expect(AccountKey.make(userID: "user-abc") != AccountKey.make(userID: "user-ABC"))
        // The same account always lands on the same key, so it finds its chats again.
        #expect(AccountKey.make(userID: "user-1") == AccountKey.make(userID: "user-1", accountID: "other"))
    }

    @Test func fallsBackWhenThereIsNoUserID() {
        #expect(AccountKey.make(userID: nil, accountID: "b23cd195-774a-45ee-bf5f-690e3a8281fe") == "b23cd195-774a-45ee-bf5f-690e3a8281fe")
        #expect(AccountKey.make(userID: "  ", accountID: nil, email: "me@example.com") == "me-example.com")
        // Nothing to go on: a key of its own, never empty.
        #expect(AccountKey.make(userID: nil).hasPrefix("account-"))
    }

    @Test func neverEscapesItsOwnFolder() {
        // Slashes and anything else unusable become "-", so what comes out is always a single path
        // component: it can look odd, but it can never climb out of the account's folder.
        #expect(AccountKey.slug("../../etc/passwd") == "..-..-etc-passwd")
        #expect(!AccountKey.slug("../../etc/passwd").contains("/"))
        #expect(AccountKey.slug("..") == "")
        #expect(AccountKey.slug(".") == "")
        #expect(AccountKey.slug("/") == "")
        #expect(AccountKey.slug("a/b\\c") == "a-b-c")
        #expect(!AccountKey.make(userID: "../..").contains("/"))
        #expect(AccountKey.slug(String(repeating: "u", count: 200)).count == 64)
    }
}

@Suite struct AccountRosterTests {
    private func account(_ key: String, addedAt: TimeInterval = 0, lastUsedAt: TimeInterval = 0) -> StoredAccount {
        StoredAccount(
            key: key,
            userID: key,
            email: "\(key)@example.com",
            addedAt: Date(timeIntervalSince1970: addedAt),
            lastUsedAt: Date(timeIntervalSince1970: lastUsedAt)
        )
    }

    @Test func addsAndSwitchesBetweenAccounts() {
        var roster = AccountRoster()
        #expect(roster.isEmpty)
        #expect(roster.current == nil)

        roster.add(account("user-1", addedAt: 10))
        roster.add(account("user-2", addedAt: 20))
        // The account just added is the one in use.
        #expect(roster.currentKey == "user-2")
        #expect(roster.accounts.count == 2)

        // `#expect` can't call a mutating member, so the switch happens first.
        let switched = roster.select("user-1", at: Date(timeIntervalSince1970: 100))
        #expect(switched)
        #expect(roster.current?.key == "user-1")
        #expect(roster.current?.lastUsedAt == Date(timeIntervalSince1970: 100))
        // Switching to an account that isn't signed in changes nothing.
        let unknown = roster.select("user-9")
        #expect(unknown == false)
        #expect(roster.currentKey == "user-1")
    }

    @Test func signingInAgainUpdatesTheAccountInPlace() {
        var roster = AccountRoster()
        roster.add(account("user-1", addedAt: 10))
        roster.add(account("user-2", addedAt: 20))
        roster.select("user-2")

        var again = account("user-1", addedAt: 999)
        again.name = "Gabriel"
        roster.add(again)
        // One row, not two, and the day it was added is kept.
        #expect(roster.accounts.count == 2)
        #expect(roster.current?.key == "user-1")
        #expect(roster.current?.name == "Gabriel")
        #expect(roster.current?.addedAt == Date(timeIntervalSince1970: 10))
    }

    @Test func removingTheCurrentAccountFallsBackToTheLatestOne() {
        var roster = AccountRoster()
        roster.add(account("user-1", addedAt: 10, lastUsedAt: 50))
        roster.add(account("user-2", addedAt: 20, lastUsedAt: 90))
        roster.add(account("user-3", addedAt: 30, lastUsedAt: 70))
        roster.select("user-3")

        let afterCurrent = roster.remove("user-3")
        #expect(afterCurrent == "user-2")
        #expect(roster.currentKey == "user-2")
        // Signing another one out leaves the current account alone.
        let afterOther = roster.remove("user-1")
        #expect(afterOther == "user-2")
        #expect(roster.currentKey == "user-2")
        // The last one out brings the sign-in screen back.
        let afterLast = roster.remove("user-2")
        #expect(afterLast == nil)
        #expect(roster.isEmpty)
        #expect(roster.currentKey == nil)
    }

    @Test func keepsTheListInTheOrderAccountsWereAdded() {
        var roster = AccountRoster()
        roster.add(account("user-3", addedAt: 30))
        roster.add(account("user-1", addedAt: 10))
        roster.add(account("user-2", addedAt: 20))
        roster.select("user-3")
        #expect(roster.ordered.map(\.key) == ["user-1", "user-2", "user-3"])
    }

    @Test func updatesWhatTheListShowsWithoutSwitching() throws {
        var roster = AccountRoster()
        roster.add(account("user-1", addedAt: 10))
        roster.add(account("user-2", addedAt: 20))
        roster.update("user-1", email: "new@example.com", name: "Gabriel", planType: "plus")
        // Empty values leave what's already known in place.
        roster.update("user-1", email: "", name: nil, planType: nil)

        let updated = try #require(roster.accounts.first { $0.key == "user-1" })
        #expect(updated.email == "new@example.com")
        #expect(updated.name == "Gabriel")
        #expect(updated.planType == "plus")
        #expect(updated.displayName == "Gabriel")
        // Updating an account doesn't make it the current one.
        #expect(roster.currentKey == "user-2")
    }

    @Test func survivesBeingSavedAndReadBack() throws {
        var roster = AccountRoster()
        roster.add(account("user-1", addedAt: 10))
        roster.add(account("user-2", addedAt: 20))
        roster.select("user-1")

        let decoded = try JSONDecoder().decode(AccountRoster.self, from: try JSONEncoder().encode(roster))
        #expect(decoded == roster)
        #expect(decoded.currentKey == "user-1")

        // A saved current account that is no longer signed in falls back to one that is.
        let repaired = AccountRoster(accounts: decoded.accounts, currentKey: "user-gone")
        #expect(repaired.currentKey == "user-1")
        #expect(AccountRoster(accounts: [], currentKey: "user-1").currentKey == nil)
    }

    @Test func namesAnAccountWithWhateverItKnows() {
        #expect(StoredAccount(key: "k", email: "me@example.com").displayName == "me@example.com")
        #expect(StoredAccount(key: "k", email: "me@example.com", name: " Gabriel ").displayName == "Gabriel")
        #expect(StoredAccount(key: "k", email: nil, name: "  ").displayName == "ChatGPT")
    }
}

@Suite struct AccountAdsSettingsTests {
    @Test func readsTheAdsSettingsOfTheAccount() throws {
        let json = #"""
        {"settings":{"bazaar_personalization_enabled":true,"bazaar_personalization_consent_set":false,
         "bazaar_history_enabled":true,"free_ads_opt_out":false,"sunshine":true,"moonshine":false,
         "training_allowed":false}}
        """#
        let settings = try #require(AccountSettings.parse(Data(json.utf8)))
        #expect(settings.adsPersonalizationEnabled == true)
        #expect(settings.adsHistoryEnabled == true)
        #expect(settings.adsPersonalizationConsentSet == false)
        #expect(settings.freeAdsOptOut == false)

        // Every switch OCTO shows reads and writes through the same key.
        #expect(settings[.adsPersonalization] == true)
        #expect(settings[.adsHistory] == true)
        #expect(settings[.freeAdsOptOut] == false)
        #expect(settings[.referencesSavedMemories] == true)
        #expect(settings[.referencesChatHistory] == false)

        var changed = settings
        changed[.freeAdsOptOut] = true
        changed[.referencesChatHistory] = true
        #expect(changed.freeAdsOptOut == true)
        #expect(changed.referencesChatHistory == true)

        // An account whose settings say nothing about ads shows no switch rather than a wrong one.
        let quiet = try #require(AccountSettings.parse(Data(#"{"settings":{"training_allowed":true}}"#.utf8)))
        #expect(quiet.adsPersonalizationEnabled == nil)
        #expect(quiet[.freeAdsOptOut] == nil)
    }

    @Test func buildsTheAdsRequests() {
        #expect(ChatGPTAccountAPI.adsProfileURL.absoluteString == "https://chatgpt.com/backend-api/bazaar/profile")
        #expect(ChatGPTAccountAPI.accountUserSettingURL(.freeAdsOptOut, value: true).absoluteString
            == "https://chatgpt.com/backend-api/settings/account_user_setting?feature=free_ads_opt_out&value=true")
        #expect(ChatGPTAccountAPI.accountUserSettingURL(.adsPersonalization, value: false).absoluteString
            == "https://chatgpt.com/backend-api/settings/account_user_setting?feature=bazaar_personalization_enabled&value=false")
        #expect(ChatGPTAccountAPI.accountUserSettingURL(.referencesSavedMemories, value: true).absoluteString
            == "https://chatgpt.com/backend-api/settings/account_user_setting?feature=sunshine&value=true")
    }
}
