import Foundation
import Testing
@testable import OCTOCore

@Suite struct AccountDeviceTests {
    @Test func buildsTheNewAccountRequests() {
        #expect(ChatGPTAccountAPI.devicesURL.absoluteString == "https://chatgpt.com/backend-api/accounts/sessions")
        #expect(ChatGPTAccountAPI.securitySettingsURL.absoluteString == "https://chatgpt.com/backend-api/accounts/security_settings/info")
        #expect(ChatGPTAccountAPI.multiFactorURL.absoluteString == "https://chatgpt.com/backend-api/accounts/mfa_info")
        #expect(ChatGPTAccountAPI.fileStorageURL.absoluteString == "https://chatgpt.com/backend-api/files/library/storage/usage")
        #expect(ChatGPTAccountAPI.conversationSearchURL(query: "carbonara").absoluteString == "https://chatgpt.com/backend-api/conversations/search?query=carbonara")
        #expect(ChatGPTAccountAPI.conversationSearchURL(query: "a b&c").absoluteString == "https://chatgpt.com/backend-api/conversations/search?query=a%20b%26c")
    }

    @Test func parsesTheDevicesOfTheAccount() throws {
        let json = #"""
        {"show_session_manager":true,"devices":[
          {"render_id":"us_old","display_name":"Mac","human_readable_description":"Mac · macOS 26.1","platform":"macos","os_version":"26.1","is_trusted_device":false,"is_current_device":false,"session_id":"us_old","last_signed_in_timestamp_second":1789127921,"last_signed_in_city":"Fondettes","last_signed_in_country":"FR","app_sessions":[{"client_name":"ChatGPT Web"},{"client_name":"ChatGPT Web"}]},
          {"render_id":"us_here","display_name":"iPhone","human_readable_description":"iPhone · iOS 26.0","platform":"ios","os_version":"26.0","is_trusted_device":true,"is_current_device":true,"session_id":"us_here","last_signed_in_timestamp_second":1789435007,"last_signed_in_city":"Limoges","last_signed_in_country":"FR","app_sessions":[{"client_name":"Codex"}]},
          {"display_name":"No id"}
        ]}
        """#
        let devices = try #require(AccountDevices.parse(Data(json.utf8)))
        #expect(devices.isManageable)
        // The device OCTO runs on comes first, then the most recent.
        #expect(devices.devices.map(\.id) == ["us_here", "us_old"])

        let current = try #require(devices.devices.first)
        #expect(current.isCurrentDevice)
        #expect(current.isTrusted)
        #expect(current.platform == "ios")
        #expect(current.apps == ["Codex"])
        #expect(current.lastSignedInAt == Date(timeIntervalSince1970: 1_789_435_007))
        #expect(current.location(locale: Locale(identifier: "en_US")) == "Limoges, France")

        // A client signed in twice on one device is listed once.
        #expect(devices.devices[1].apps == ["ChatGPT Web"])

        #expect(AccountDevices.parse(Data(#"{"devices":[]}"#.utf8))?.isEmpty == true)
        #expect(AccountDevices.parse(Data(#"{"foo":1}"#.utf8)) == nil)
    }

    @Test func parsesHowTheAccountIsProtected() throws {
        let settings = Data(#"{"advanced_protection_mode_enabled":false,"login_notification_mode":"new_devices","aas_eligible":true}"#.utf8)
        let mfa = Data(#"""
        {"mfa_enabled":true,"mfa_enabled_v2":true,"factors":{"totp":[{"id":"t1","factor_type":"totp","metadata":null}],"push_auth":{"id":"p1","factor_type":"push_auth"},"passkeys":[{"id":"k1","metadata":{"authenticator_name":"Proton Pass"}}],"sms":[]}}
        """#.utf8)

        let security = try #require(AccountSecurity.parse(settings: settings, multiFactor: mfa))
        #expect(security.advancedProtectionEnabled == false)
        #expect(security.loginNotificationMode == "new_devices")
        #expect(security.multiFactorEnabled == true)
        #expect(security.factors.map(\.kind) == [.authenticator, .passkey, .push])
        #expect(security.factors.first(where: { $0.kind == .passkey })?.name == "Proton Pass")

        // Either call can be refused on its own; what came back still shows.
        let partial = try #require(AccountSecurity.parse(settings: settings, multiFactor: nil))
        #expect(partial.multiFactorEnabled == nil)
        #expect(partial.factors.isEmpty)
        #expect(AccountSecurity.parse(settings: nil, multiFactor: nil) == nil)
        #expect(AccountSecurity.parse(settings: Data(#"{}"#.utf8), multiFactor: nil) == nil)
    }

    @Test func parsesTheFileStorageOfTheAccount() throws {
        let json = #"""
        {"plan_type":"free","used_bytes":20231796,"allowed_bytes":536870912,"remaining_bytes":516639116,"is_over_limit":false,
         "breakdown_by_file_type":[{"file_type":"text","used_bytes":14675,"count":1},{"file_type":"image","used_bytes":19060546,"count":13},{"file_type":"empty","used_bytes":0,"count":0}],
         "breakdown_by_source":[{"source":"uploaded","used_bytes":16127770},{"source":"generated","used_bytes":4104026}]}
        """#
        let storage = try #require(AccountFileStorage.parse(Data(json.utf8)))
        #expect(storage.usedBytes == 20_231_796)
        #expect(storage.allowedBytes == 536_870_912)
        #expect(storage.isOverLimit == false)
        // Biggest slice first, and empty ones left out.
        #expect(storage.byFileType.map(\.key) == ["image", "text"])
        #expect(storage.byFileType.first?.count == 13)
        #expect(storage.bySource.map(\.key) == ["uploaded", "generated"])
        let fraction = try #require(storage.usedFraction)
        #expect(abs(fraction - 0.0376) < 0.001)

        #expect(AccountFileStorage.parse(Data(#"{"used_bytes":10}"#.utf8))?.usedFraction == nil)
        #expect(AccountFileStorage.parse(Data(#"{"foo":1}"#.utf8)) == nil)
    }

    @Test func parsesSearchResultsWhateverTheirWrapper() throws {
        let json = #"""
        {"items":[
          {"conversation_id":"6aa93755-fcbc-83eb-9c2e-7a77d8494315","title":" Carbonara ","snippet":"the real <em>carbonara</em>\nhas no cream","update_time":"2026-09-15T13:27:37.187233Z","gizmo_id":null},
          {"id":"other","title":"In a project","highlight":"<mark>pasta</mark>","create_time":"2026-09-01T10:00:00Z","gizmo_id":"g-p-1"},
          {"conversation_id":"6aa93755-fcbc-83eb-9c2e-7a77d8494315","title":"Duplicate"},
          {"title":"No id"}
        ]}
        """#
        let hits = try #require(RemoteSearchResults.parse(Data(json.utf8)))
        #expect(hits.map(\.id) == ["6aa93755-fcbc-83eb-9c2e-7a77d8494315", "other"])
        #expect(hits[0].title == "Carbonara")
        #expect(hits[0].snippet == "the real carbonara has no cream")
        #expect(hits[0].updatedAt != nil)
        #expect(hits[1].projectID == "g-p-1")
        #expect(hits[1].snippet == "pasta")
        // A hit opens like any other chat of the account.
        #expect(hits[0].summary.id == hits[0].id)

        // The wrapper has been named differently over time, and a bare list is accepted too.
        #expect(RemoteSearchResults.parse(Data(#"{"conversations":[{"id":"a","title":"A"}]}"#.utf8))?.count == 1)
        #expect(RemoteSearchResults.parse(Data(#"[{"id":"a","title":"A"}]"#.utf8))?.count == 1)
        #expect(RemoteSearchResults.parse(Data(#"{"items":[]}"#.utf8))?.isEmpty == true)
        #expect(RemoteSearchResults.parse(Data(#"{"detail":"not found"}"#.utf8)) == nil)
    }
}
