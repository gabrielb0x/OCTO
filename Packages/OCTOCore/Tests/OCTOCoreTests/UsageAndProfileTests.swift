import Foundation
import Testing
@testable import OCTOCore

@Suite struct TelemetryBlocklistTests {
    @Test func blocksTheTelemetryOfChatGPTAndCodex() throws {
        let blocked = [
            "https://chatgpt.com/ces/v1/rgstr?k=client-abc&st=javascript-client&sv=3.33.1",
            "https://api.oaistatsig.com/v1/sdk_exception",
            "https://chatgpt.com/ces/statsc/flush",
            "https://chatgpt.com/ces/v1/telemetry/intake?ddforward=%2Fapi%2Fv2%2Flogs",
            "https://chatgpt.com/ces/v1/projects/oai/settings",
            "https://chatgpt.com/backend-api/lat/r",
            "https://chatgpt.com/backend-api/personality_settings_impression",
            "https://chatgpt.com/backend-api/codex/analytics-events/events",
            "https://ab.chatgpt.com/otlp/v1/metrics",
            "https://ab.chatgpt.com/v1/initialize",
            "https://events.statsigapi.net/v1/rgstr",
            "https://o33249.ingest.sentry.io/api/1/envelope/",
            "https://browser-intake-datadoghq.com/api/v2/rum",
            "https://www.google-analytics.com/g/collect",
            "https://example.com/v1/rgstr",
            "https://CHATGPT.COM/CES/v1/t",
        ]
        for address in blocked {
            let url = try #require(URL(string: address))
            #expect(TelemetryBlocklist.blocks(url), "\(address) should be blocked")
        }
        let statsig = try #require(URL(string: "https://api.oaistatsig.com/v1/sdk_exception"))
        #expect(TelemetryBlocklist.rule(for: statsig)?.pattern == "oaistatsig.com")
        let events = try #require(URL(string: "https://chatgpt.com/ces/v1/rgstr"))
        #expect(TelemetryBlocklist.rule(for: events)?.pattern == "chatgpt.com/ces/")
    }

    @Test func letsEverythingOCTONeedsThrough() throws {
        let allowed = [
            "https://chatgpt.com/backend-api/me",
            "https://chatgpt.com/backend-api/codex/responses",
            "https://chatgpt.com/backend-api/codex/models?client_version=0.155.0",
            "https://chatgpt.com/backend-api/wham/usage",
            "https://chatgpt.com/backend-api/wham/profiles/me",
            "https://chatgpt.com/backend-api/calpico/chatgpt/profile/user-1",
            "https://chatgpt.com/backend-api/conversation/6aa78bc8-756c-83eb-b946-e17ad6461b0a",
            "https://chatgpt.com/backend-api/estuary/public_content/enc/abc",
            "https://auth.openai.com/oauth/token",
            "https://api.github.com/repos/gabrielb0x/OCTO/releases/latest",
            "https://notstatsig.com/",
            "https://example.com/ces/v1/t",
        ]
        for address in allowed {
            let url = try #require(URL(string: address))
            #expect(!TelemetryBlocklist.blocks(url), "\(address) should go through")
        }
    }
}

@Suite struct SocialProfileTests {
    @Test func parsesTheProfileOfGroupChats() throws {
        let json = #"{"user_id":"user-jVx2J6OrAoaK6OEsnCk8PyYy","username":"0x82","display_name":"ㅤ0xahhhhh","profile_picture_url":"https://chatgpt.com/backend-api/estuary/public_content/enc/eyJpZCI6InVzZXIifQ","likeness_picture_url":null,"bio_freeform":null,"bio_snippets":null,"location":null,"work":null,"schools":null,"connection_state":null}"#
        let profile = try #require(SocialProfile.parse(Data(json.utf8)))
        #expect(profile.userID == "user-jVx2J6OrAoaK6OEsnCk8PyYy")
        #expect(profile.username == "0x82")
        #expect(profile.displayName == "ㅤ0xahhhhh")
        #expect(profile.pictureURL == URL(string: "https://chatgpt.com/backend-api/estuary/public_content/enc/eyJpZCI6InVzZXIifQ"))

        let empty = try #require(SocialProfile.parse(Data(#"{"user_id":"user-2","username":" ","display_name":null,"profile_picture_url":""}"#.utf8)))
        #expect(empty == SocialProfile(userID: "user-2"))
        #expect(SocialProfile.parse(Data(#"{"username":"x"}"#.utf8)) == nil)
    }

    @Test func buildsTheCallsOfEditProfile() throws {
        #expect(SocialProfileAPI.profileURL(userID: "user-1").absoluteString == "https://chatgpt.com/backend-api/calpico/chatgpt/profile/user-1")
        #expect(SocialProfileAPI.usernameURL(userID: "user-1").absoluteString == "https://chatgpt.com/backend-api/calpico/chatgpt/profile/user-1/username")
        #expect(SocialProfileAPI.profileURL(userID: "../me").absoluteString == "https://chatgpt.com/backend-api/calpico/chatgpt/profile/..%2Fme")
        #expect(SocialProfileAPI.photoUploadURL.absoluteString == "https://chatgpt.com/backend-api/calpico/chatgpt/profile_files")
        #expect(SocialProfileAPI.codexPhotoUploadURL.absoluteString == "https://chatgpt.com/backend-api/wham/profiles/me/photo")

        let name = try #require(JSONValue.object(SocialProfileAPI.displayNameBody("Gabriel")))
        #expect(name.count == 1)
        #expect(JSONValue.string(name["display_name"]) == "Gabriel")
        let username = try #require(JSONValue.object(SocialProfileAPI.usernameBody("0x82")))
        #expect(JSONValue.string(username["username"]) == "0x82")
        let photo = try #require(JSONValue.object(SocialProfileAPI.photoBody(assetPointer: "sediment://file_123")))
        #expect(JSONValue.string(photo["profile_asset_pointer"]) == "sediment://file_123")

        #expect(SocialProfileAPI.assetPointer(in: Data(#"{"asset_pointer":"sediment://file_123"}"#.utf8)) == "sediment://file_123")
        #expect(SocialProfileAPI.assetPointer(in: Data(#"{"asset_pointer":""}"#.utf8)) == nil)
        let nested = SocialProfileAPI.profile(inCodexResponse: Data(#"{"profile":{"username":"0x82","profile_picture_url":"https://chatgpt.com/p.png"}}"#.utf8), userID: "user-1")
        #expect(nested == SocialProfile(userID: "user-1", username: "0x82", pictureURL: URL(string: "https://chatgpt.com/p.png")))

        let form = String(decoding: SocialProfileAPI.photoForm(jpeg: Data([0xFF, 0xD8])).encoded(), as: UTF8.self)
        #expect(form.contains("name=\"file\"; filename=\"profile.jpg\""))
        #expect(form.contains("Content-Type: image/jpeg"))

        #expect(SocialProfileAPI.normalizedUsername("  @@0x82 ") == "0x82")
        #expect(SocialProfileAPI.normalizedDisplayName("  Gabriel\n") == "Gabriel")
    }
}

@Suite struct CodexUsageTests {
    private let day: TimeInterval = 86_400

    @Test func readsTheTokensOfEachDay() throws {
        let json = #"{"profile":{"username":"0x82"},"stats":{"lifetime_tokens":123456,"peak_daily_tokens":45000,"longest_running_turn_sec":67,"current_streak_days":3,"longest_streak_days":9,"daily_usage_buckets":[{"start_date":"2026-09-17","tokens":1000},{"start_date":"2026-09-19","tokens":2500},{"start_date":"2026-09-18","tokens":0},{"start_date":"nope","tokens":7}]}}"#
        let activity = try #require(CodexTokenActivity.parse(Data(json.utf8)))
        #expect(activity.lifetimeTokens == 123_456)
        #expect(activity.peakDailyTokens == 45_000)
        #expect(activity.currentStreakDays == 3)
        #expect(activity.days.map(\.tokens) == [1_000, 2_500])
        let september17 = try #require(FlexibleDate.parse("2026-09-17T00:00:00Z"))
        #expect(activity.days.first?.date == september17)

        let now = september17.addingTimeInterval(2 * day + 3_600)
        #expect(activity.tokens(since: september17.addingTimeInterval(day + 60)) == 2_500)
        #expect(activity.tokens(since: september17.addingTimeInterval(-5 * day)) == 3_500)
        let recent = activity.recentDays(4, now: now)
        #expect(recent.map(\.tokens) == [0, 1_000, 0, 2_500])
        #expect(recent.last?.date == september17.addingTimeInterval(2 * day))

        #expect(CodexTokenActivity.parse(Data(#"{"stats":{}}"#.utf8)) == nil)
        let local = CodexTokenActivity(samples: [TokenSample(date: september17.addingTimeInterval(60), tokens: 10), TokenSample(date: september17.addingTimeInterval(120), tokens: 5)])
        #expect(local.days == [CodexTokenActivity.Day(date: september17, tokens: 15)])
        #expect(local.lifetimeTokens == 15)
    }

    @Test func readsTheLimitsSentWithAReply() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let headers = [
            "X-Codex-Primary-Used-Percent": "12.5",
            "x-codex-primary-window-minutes": "300",
            "x-codex-primary-reset-at": "5000",
            "x-codex-secondary-used-percent": "40",
            "x-codex-secondary-window-minutes": "10080",
            "x-codex-secondary-reset-after-seconds": "600",
            "content-type": "text/event-stream",
        ]
        let limits = try #require(CodexRateLimits.parse(headers: headers, now: now))
        #expect(limits.primary == UsageSnapshot.Window(usedPercent: 12.5, windowSeconds: 18_000, resetsAt: Date(timeIntervalSince1970: 5_000)))
        #expect(limits.secondary == UsageSnapshot.Window(usedPercent: 40, windowSeconds: 604_800, resetsAt: Date(timeIntervalSince1970: 1_600)))
        #expect(CodexRateLimits.parse(headers: ["content-type": "text/event-stream"]) == nil)

        let event = #"{"type":"codex.rate_limits","plan_type":"plus","rate_limits":{"primary":{"used_percent":7,"window_minutes":300,"reset_at":9000},"secondary":null}}"#
        #expect(ResponseStreamDecoder.updates(fromEventData: event) == [.rateLimits(CodexRateLimits(primary: UsageSnapshot.Window(usedPercent: 7, windowSeconds: 18_000, resetsAt: Date(timeIntervalSince1970: 9_000))))])

        // A reply only tells how much is used: when the limit resets is kept from before.
        let known = UsageSnapshot(limits: CodexRateLimits(primary: UsageSnapshot.Window(usedPercent: 1, windowSeconds: 2_592_000, resetsAt: Date(timeIntervalSince1970: 50_000))))
        let updated = known.applying(CodexRateLimits(primary: UsageSnapshot.Window(usedPercent: 100)))
        #expect(updated.primary == UsageSnapshot.Window(usedPercent: 100, windowSeconds: 2_592_000, resetsAt: Date(timeIntervalSince1970: 50_000)))
        #expect(updated.limitReached)
        #expect(updated.mostUsedWindow?.leftPercent == 0)
    }

    @Test func estimatesWhatIsLeftFromWhatWasUsed() throws {
        let now = try #require(FlexibleDate.parse("2026-09-19T12:00:00Z"))
        // A 30-day limit, 10 % used, that started 10 days ago.
        let monthly = UsageSnapshot.Window(usedPercent: 10, windowSeconds: 30 * 86_400, resetsAt: now.addingTimeInterval(20 * day))
        let activity = CodexTokenActivity(days: [
            CodexTokenActivity.Day(date: CodexTokenActivity.dayStart(now.addingTimeInterval(-40 * day)), tokens: 99_999),
            CodexTokenActivity.Day(date: CodexTokenActivity.dayStart(now.addingTimeInterval(-3 * day)), tokens: 30_000),
            CodexTokenActivity.Day(date: CodexTokenActivity.dayStart(now), tokens: 20_000),
        ])
        let usage = UsageSnapshot(limits: CodexRateLimits(primary: monthly))
        let estimate = try #require(CodexUsageEstimator.estimate(usage: usage, activity: activity, samples: [], tokensPerMessage: 2_000, now: now))
        #expect(estimate.tokensUsed == 50_000)
        #expect(estimate.tokensTotal == 500_000)
        #expect(estimate.tokensLeft == 450_000)
        #expect(estimate.messagesLeft == 225)

        // A 5-hour limit can't be read from days: the replies of this device count instead, and
        // the limit leaving the fewest tokens wins.
        let fiveHours = UsageSnapshot.Window(usedPercent: 50, windowSeconds: 18_000, resetsAt: now.addingTimeInterval(3_600))
        let samples = [TokenSample(date: now.addingTimeInterval(-600), tokens: 40_000), TokenSample(date: now.addingTimeInterval(-86_400), tokens: 1_000_000)]
        let both = UsageSnapshot(limits: CodexRateLimits(primary: fiveHours, secondary: monthly))
        let tighter = try #require(CodexUsageEstimator.estimate(usage: both, activity: activity, samples: samples, tokensPerMessage: nil, now: now))
        #expect(tighter.window == fiveHours)
        #expect(tighter.tokensLeft == 40_000)
        #expect(tighter.messagesLeft == nil)

        // Nothing used yet: the size of the limit can't be told.
        let unused = UsageSnapshot(limits: CodexRateLimits(primary: UsageSnapshot.Window(usedPercent: 0, windowSeconds: 30 * 86_400, resetsAt: now.addingTimeInterval(day))))
        #expect(CodexUsageEstimator.estimate(usage: unused, activity: activity, samples: [], tokensPerMessage: 100, now: now) == nil)
        // A limit reached leaves nothing.
        let reached = UsageSnapshot(limits: CodexRateLimits(primary: UsageSnapshot.Window(usedPercent: 100, windowSeconds: 30 * 86_400, resetsAt: now.addingTimeInterval(day))))
        #expect(CodexUsageEstimator.estimate(usage: reached, activity: activity, samples: [], tokensPerMessage: 100, now: now)?.messagesLeft == 0)
    }

    @Test func weighsAMessageFromTheHistory() throws {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let measured = Conversation(messages: [
            ChatMessage(role: .user, text: "Hi", createdAt: start),
            ChatMessage(role: .assistant, text: "Hello!", usage: TokenUsage(inputTokens: 1_200, cachedInputTokens: 1_000, outputTokens: 150, reasoningTokens: 100), createdAt: start.addingTimeInterval(1)),
        ])
        // 400 characters of question and 800 of reply, with 400 of instructions: at 4 characters a
        // token — too few replies were counted to measure better — it sent 200 tokens and wrote 200.
        let estimated = Conversation(messages: [
            ChatMessage(role: .user, text: String(repeating: "a", count: 400), createdAt: start.addingTimeInterval(10)),
            ChatMessage(role: .assistant, text: String(repeating: "b", count: 800), createdAt: start.addingTimeInterval(11)),
            ChatMessage(role: .assistant, text: "", status: .failed, createdAt: start.addingTimeInterval(12)),
        ])
        let average = try #require(MessageCost.average(of: [measured, estimated], instructionsCharacters: 400))
        #expect(average.replies == 2)
        #expect(average.measuredReplies == 1)
        #expect(average.tokens == (1_350 + 400) / 2)
        #expect(MessageCost.measuredSamples(in: [measured, estimated]) == [TokenSample(date: start.addingTimeInterval(1), tokens: 1_350)])
        #expect(MessageCost.average(of: [], instructionsCharacters: 0) == nil)
    }
}
