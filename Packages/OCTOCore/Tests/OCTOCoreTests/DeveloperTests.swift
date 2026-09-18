import Foundation
import Testing
@testable import OCTOCore

@Suite struct PlanTests {
    @Test func tellsFreePlansFromSubscriptions() {
        #expect(ChatGPTPlan.isPaid("free") == false)
        #expect(ChatGPTPlan.isPaid(" FREE ") == false)
        #expect(ChatGPTPlan.isPaid("free_workspace") == false)
        #expect(ChatGPTPlan.isPaid("go") == true)
        #expect(ChatGPTPlan.isPaid("plus") == true)
        #expect(ChatGPTPlan.isPaid(nil) == nil)
        #expect(ChatGPTPlan.isPaid("") == nil)
    }

    @Test func parsesTheSubscription() throws {
        let json = #"""
        {"accounts":{
          "acc-1":{"account":{"account_id":"acc-1","plan_type":"plus","structure":"personal","name":null},"features":["b_feature","a_feature"],
                   "entitlement":{"subscription_id":"sub_1","has_active_subscription":true,"subscription_plan":"chatgptplusplan","expires_at":"2026-10-14T08:00:00+00:00","billing_period":"monthly"},
                   "last_active_subscription":{"subscription_id":"sub_1","purchase_origin_platform":"chatgpt_mobile_ios","will_renew":true}},
          "default":{"account":{"plan_type":"free","structure":"workspace","name":"Team"},"entitlement":{"has_active_subscription":false,"expires_at":null}}
        },"account_ordering":["default","acc-1"]}
        """#
        let plus = try #require(AccountSubscription.parse(Data(json.utf8), accountID: "acc-1"))
        #expect(plus.planType == "plus")
        #expect(plus.hasActiveSubscription)
        #expect(plus.expiresAt == FlexibleDate.parse("2026-10-14T08:00:00Z"))
        #expect(plus.willRenew == true)
        #expect(plus.billingPeriod == "monthly")
        #expect(plus.store == .appStore)
        #expect(plus.workspaceName == nil)
        #expect(plus.features == ["a_feature", "b_feature"])

        let first = try #require(AccountSubscription.parse(Data(json.utf8), accountID: nil))
        #expect(first.planType == "free")
        #expect(first.expiresAt == nil)
        #expect(first.workspaceName == "Team")
        #expect(first.store == nil)

        #expect(AccountSubscription.parse(Data(json.utf8), accountID: "missing")?.planType == "free")
        #expect(AccountSubscription.parse(Data(#"{"accounts":{}}"#.utf8), accountID: nil) == nil)
    }

    @Test func formatsTokenClaims() throws {
        let payload = Base64URL.encode(Data(#"{"b":1,"a":"https://api.openai.com/auth"}"#.utf8))
        let pretty = try #require(JWT.prettyPayload(of: "header.\(payload).signature"))
        let a = try #require(pretty.range(of: "\"a\""))
        let b = try #require(pretty.range(of: "\"b\""))
        #expect(a.lowerBound < b.lowerBound)
        #expect(pretty.contains("https://api.openai.com/auth"))
        #expect(JWT.prettyPayload(of: "not-a-token") == nil)
    }
}

@Suite struct DeveloperToolsTests {
    @Test func keepsConsoleRequestsInsideBackendAPI() {
        #expect(ChatGPTAccountAPI.consoleURL(path: "me")?.absoluteString == "https://chatgpt.com/backend-api/me")
        #expect(ChatGPTAccountAPI.consoleURL(path: " /backend-api/settings/user ")?.absoluteString == "https://chatgpt.com/backend-api/settings/user")
        #expect(ChatGPTAccountAPI.consoleURL(path: "https://chatgpt.com/backend-api/conversations?offset=0&limit=5")?.absoluteString == "https://chatgpt.com/backend-api/conversations?offset=0&limit=5")
        #expect(ChatGPTAccountAPI.consoleURL(path: "codex/models?client_version=1.0")?.path == "/backend-api/codex/models")
        #expect(ChatGPTAccountAPI.accountCheckURL.absoluteString == "https://chatgpt.com/backend-api/accounts/check/v4-2023-04-27")

        for rejected in ["", "/", "../v1/models", "codex/../../x", "codex/%2e%2e/me", "a//b", "https://example.com/backend-api/me", "me#top", "gizmos\\x"] {
            #expect(ChatGPTAccountAPI.consoleURL(path: rejected) == nil, "\(rejected)")
        }
    }

    @Test func redactsCredentials() throws {
        let headers = HTTPLogRedactor.headers(["Authorization": "Bearer abc.def", "ChatGPT-Account-ID": "acc", "Cookie": "x=1", "proxy-authorization": "secret"])
        #expect(headers["Authorization"] == "Bearer <redacted>")
        #expect(headers["ChatGPT-Account-ID"] == "acc")
        #expect(headers["Cookie"] == "<redacted>")
        #expect(headers["proxy-authorization"] == "<redacted>")

        let json = #"{"access_token":"a","refresh_token":"r","error":{"code":"invalid_grant","message":"Nope"},"items":[{"id_token":"i","title":"Trip"}],"token":null}"#
        let body = try #require(HTTPLogRedactor.body(Data(json.utf8), contentType: "application/json; charset=utf-8"))
        let object = try #require(JSONValue.object(Data(body.utf8)))
        #expect(JSONValue.string(object["access_token"]) == "<redacted>")
        #expect(JSONValue.string(object["refresh_token"]) == "<redacted>")
        #expect(object["token"] is NSNull)
        let error = try #require(object["error"] as? [String: Any])
        #expect(JSONValue.string(error["code"]) == "invalid_grant")
        let item = try #require((object["items"] as? [[String: Any]])?.first)
        #expect(JSONValue.string(item["id_token"]) == "<redacted>")
        #expect(JSONValue.string(item["title"]) == "Trip")

        let form = HTTPLogRedactor.body(Data("grant_type=authorization_code&code=secret&code_verifier=v&client_id=app".utf8), contentType: "application/x-www-form-urlencoded")
        #expect(form == "grant_type=authorization_code&code=<redacted>&code_verifier=<redacted>&client_id=app")
        #expect(HTTPLogRedactor.body(Data([0xFF, 0xD8, 0xFF]), contentType: "image/jpeg") == "<3 bytes>")
        #expect(HTTPLogRedactor.body(Data(), contentType: "text/plain") == nil)
        #expect(HTTPLogRedactor.body(Data(#"{"refresh_token": "abc", "#.utf8), contentType: "application/json") == #"{"refresh_token": "<redacted>", "#)
        let jwt = "eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiJ1c2VyLTEifQ.c2lnbmF0dXJlLXZhbHVl"
        #expect(HTTPLogRedactor.body(Data("data: \(jwt)".utf8), contentType: "text/event-stream") == "data: <redacted>")
        #expect(HTTPLogRedactor.body(Data("abcdefghij-more".utf8), contentType: "text/plain", limit: 10) == "abcdefghij…")

        let callback = try #require(URL(string: "http://localhost:1455/auth/callback?code=abc&state=xyz#done"))
        #expect(HTTPLogRedactor.url(callback) == "http://localhost:1455/auth/callback?code=<redacted>&state=xyz#done")

        let curl = HTTPLogRedactor.curlCommand(
            method: "POST",
            url: try #require(URL(string: "https://chatgpt.com/backend-api/me")),
            headers: ["Authorization": "Bearer <redacted>", "Accept": "application/json"],
            body: #"{"title":"it's"}"#
        )
        #expect(curl.hasPrefix("curl -X POST 'https://chatgpt.com/backend-api/me'"))
        #expect(curl.contains("-H 'Accept: application/json'"))
        #expect(curl.contains(#"-H "Authorization: Bearer $CHATGPT_ACCESS_TOKEN""#))
        #expect(curl.contains(#"--data-raw '{"title":"it'\''s"}'"#))
    }

    @Test func unlocksAfterEightQuickTaps() {
        var unlock = DeveloperUnlock()
        let start = Date(timeIntervalSince1970: 1_000)
        for index in 0..<7 {
            #expect(unlock.registerTap(at: start.addingTimeInterval(Double(index) * 0.3)) == .counting(remaining: 7 - index))
        }
        #expect(unlock.registerTap(at: start.addingTimeInterval(2.1)) == .unlocked)
        #expect(unlock.registerTap(at: start.addingTimeInterval(2.2)) == .counting(remaining: 7))

        var slow = DeveloperUnlock(requiredTaps: 3, maximumGap: 1)
        #expect(slow.registerTap(at: start) == .counting(remaining: 2))
        #expect(slow.registerTap(at: start.addingTimeInterval(0.5)) == .counting(remaining: 1))
        #expect(slow.registerTap(at: start.addingTimeInterval(2)) == .counting(remaining: 2))
    }

    @Test func locksAfterTheTimeout() {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(AppLockPolicy.requiresUnlock(isEnabled: true, backgroundedAt: nil, now: now, timeout: 300))
        #expect(!AppLockPolicy.requiresUnlock(isEnabled: false, backgroundedAt: nil, now: now, timeout: 0))
        #expect(!AppLockPolicy.requiresUnlock(isEnabled: true, backgroundedAt: now.addingTimeInterval(-60), now: now, timeout: 300))
        #expect(AppLockPolicy.requiresUnlock(isEnabled: true, backgroundedAt: now.addingTimeInterval(-300), now: now, timeout: 300))
        #expect(AppLockPolicy.requiresUnlock(isEnabled: true, backgroundedAt: now, now: now, timeout: 0))
    }

    @Test func prefillsGitHubIssues() throws {
        let repository = try #require(URL(string: "https://github.com/gabrielb0x/OCTO"))
        let body = IssueReport.body(description: " The refresh fails ", diagnostics: [("Version", "1.2.0 (3)"), ("Device", "iPhone|17")], log: "sync failed")
        #expect(body.hasPrefix("The refresh fails\n\n| | |"))
        #expect(body.contains("| Device | iPhone/17 |"))
        #expect(body.contains("```\nsync failed\n```"))

        let url = IssueReport.newIssueURL(repository: repository, title: "Bug: refresh", body: body)
        #expect(url.absoluteString.hasPrefix("https://github.com/gabrielb0x/OCTO/issues/new?title=Bug%3A%20refresh&body=The%20refresh%20fails"))

        let long = IssueReport.newIssueURL(repository: repository, title: "Long", body: String(repeating: "é", count: 20_000), maximumLength: 2_000)
        #expect(long.absoluteString.count <= 2_000)
        #expect(long.absoluteString.hasSuffix("%0A%0A%E2%80%A6"))
    }
}
