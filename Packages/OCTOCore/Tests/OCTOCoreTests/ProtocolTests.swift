import Foundation
import Testing
@testable import OCTOCore

@Suite struct ResponseStreamDecoderTests {
    @Test func decodesTextReasoningAndCompletion() {
        #expect(ResponseStreamDecoder.updates(fromEventData: #"{"type":"response.output_item.added","item":{"type":"reasoning","id":"rs_1"}}"#) == [.reasoningStarted])
        #expect(ResponseStreamDecoder.updates(fromEventData: #"{"type":"response.reasoning_summary_text.delta","delta":"Thinking"}"#) == [.reasoningDelta("Thinking")])
        #expect(ResponseStreamDecoder.updates(fromEventData: #"{"type":"response.output_text.delta","delta":"Hi"}"#) == [.textDelta("Hi")])
        let completed = ResponseStreamDecoder.updates(fromEventData: #"{"type":"response.completed","response":{"usage":{"input_tokens":10,"input_tokens_details":{"cached_tokens":4},"output_tokens":7,"output_tokens_details":{"reasoning_tokens":3}}}}"#)
        #expect(completed == [.completed(TokenUsage(inputTokens: 10, cachedInputTokens: 4, outputTokens: 7, reasoningTokens: 3))])
        #expect(ResponseStreamDecoder.updates(fromEventData: "[DONE]").isEmpty)
        #expect(ResponseStreamDecoder.updates(fromEventData: #"{"type":"response.in_progress"}"#).isEmpty)
    }

    @Test func decodesWebSearchAndCitations() {
        #expect(ResponseStreamDecoder.updates(fromEventData: #"{"type":"response.output_item.done","item":{"type":"web_search_call","action":{"type":"search","query":"weather paris"}}}"#) == [.webSearchFinished(query: "weather paris")])
        let message = #"{"type":"response.output_item.done","item":{"type":"message","content":[{"type":"output_text","text":"x","annotations":[{"type":"url_citation","url":"https://www.example.com/a","title":"Example"}]}]}}"#
        #expect(ResponseStreamDecoder.updates(fromEventData: message) == [.citations([Citation(url: "https://www.example.com/a", title: "Example")])])
        #expect(Citation(url: "https://www.example.com/a").host == "example.com")
    }

    @Test func decodesFailures() {
        let failed = ResponseStreamDecoder.updates(fromEventData: #"{"type":"response.failed","response":{"error":{"code":"context_length_exceeded","message":"Too long"}}}"#)
        #expect(failed == [.failed(ResponseStreamFailure(code: "context_length_exceeded", message: "Too long"))])
        #expect(ChatFailureKind.classify(ResponseStreamFailure(code: "context_length_exceeded", message: "Too long")) == .contextTooLong)
        let error = ResponseStreamDecoder.updates(fromEventData: #"{"type":"error","code":"rate_limit_exceeded","message":"Slow down"}"#)
        #expect(error == [.failed(ResponseStreamFailure(code: "rate_limit_exceeded", message: "Slow down"))])
    }

    @Test func classifiesHTTPErrorBodies() {
        let usage = APIErrorPayload.parse(Data(#"{"error":{"type":"usage_limit_reached","message":"Limit","plan_type":"plus","resets_at":1700000000}}"#.utf8))
        #expect(usage.planType == "plus")
        #expect(ChatFailureKind.classify(status: 429, payload: usage) == .usageLimitReached(resetsAt: Date(timeIntervalSince1970: 1_700_000_000)))
        let detail = APIErrorPayload.parse(Data(#"{"detail":"Unsupported model"}"#.utf8))
        #expect(detail.message == "Unsupported model")
        #expect(ChatFailureKind.classify(status: 400, payload: detail) == .invalidRequest("Unsupported model"))
        #expect(ChatFailureKind.classify(status: 401, payload: APIErrorPayload()) == .unauthorized)
        #expect(ChatFailureKind.classify(status: 403, payload: APIErrorPayload.parse(Data("<html>".utf8))) == .blocked(nil))
    }

    @Test func parsesUsageSnapshot() {
        let now = Date(timeIntervalSince1970: 1_000)
        let json = #"{"plan_type":"pro","rate_limit":{"allowed":true,"limit_reached":false,"primary_window":{"used_percent":42,"limit_window_seconds":18000,"reset_after_seconds":600,"reset_at":0},"secondary_window":{"used_percent":7,"limit_window_seconds":604800,"reset_after_seconds":0,"reset_at":5000}},"credits":{"has_credits":false,"unlimited":false,"balance":null}}"#
        let snapshot = UsageSnapshot.parse(Data(json.utf8), now: now)
        #expect(snapshot?.planType == "pro")
        #expect(snapshot?.limitReached == false)
        #expect(snapshot?.primary == UsageSnapshot.Window(usedPercent: 42, windowSeconds: 18_000, resetsAt: Date(timeIntervalSince1970: 1_600)))
        #expect(snapshot?.secondary?.resetsAt == Date(timeIntervalSince1970: 5_000))
        #expect(snapshot?.hasCredits == false)
        #expect(snapshot?.creditBalance == nil)
    }
}

@Suite struct AuthTests {
    static func jwt(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        return "e30.\(Base64URL.encode(data)).signature"
    }

    @Test func readsChatGPTClaims() {
        let idToken = Self.jwt(["email": "me@example.com", "https://api.openai.com/auth": ["chatgpt_plan_type": "plus", "chatgpt_account_id": "acc_123", "chatgpt_user_id": "user_1"]])
        let accessToken = Self.jwt(["exp": 1_900_000_000])
        let claims = ChatGPTAccountClaims(idToken: idToken, accessToken: accessToken)
        #expect(claims.email == "me@example.com")
        #expect(claims.planType == "plus")
        #expect(claims.accountID == "acc_123")
        #expect(claims.userID == "user_1")
        #expect(claims.accessTokenExpiresAt == Date(timeIntervalSince1970: 1_900_000_000))
        #expect(ChatGPTPlan.displayName(for: "plus") == "Plus")
        #expect(ChatGPTPlan.displayName(for: "self_serve_business_usage_based") == "Business")
    }

    @Test func buildsAuthorizeURLAndParsesCallback() {
        let url = OpenAIAuth.authorizeURL(codeChallenge: "abc", state: "xyz")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let values = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        #expect(url.absoluteString.hasPrefix("https://auth.openai.com/oauth/authorize?"))
        #expect(values["client_id"] == "app_EMoamEEZ73f0CkXaXp7hrann")
        #expect(values["redirect_uri"] == "http://localhost:1455/auth/callback")
        #expect(values["scope"] == "openid profile email offline_access")
        #expect(values["code_challenge"] == "abc")
        #expect(values["code_challenge_method"] == "S256")
        #expect(values["originator"] == "codex_cli_rs")
        #expect(OAuthCallback.parse(query: "code=a%2Bb&state=xyz", expectedState: "xyz") == .code("a+b"))
        #expect(OAuthCallback.parse(query: "code=a&state=other", expectedState: "xyz") == nil)
        #expect(OAuthCallback.parse(query: "error=access_denied&state=xyz", expectedState: "xyz") == .failure("access_denied"))
    }

    @Test func encodesTokenRequests() {
        let body = String(decoding: OpenAIAuth.authorizationCodeBody(code: "c/d+e", codeVerifier: "v"), as: UTF8.self)
        #expect(body == "grant_type=authorization_code&code=c%2Fd%2Be&redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback&client_id=app_EMoamEEZ73f0CkXaXp7hrann&code_verifier=v")
        let refresh = JSONValue.object(OpenAIAuth.refreshBody(refreshToken: "r"))
        #expect(JSONValue.string(refresh?["grant_type"]) == "refresh_token")
        #expect(JSONValue.string(refresh?["client_id"]) == OpenAIAuth.clientID)
        #expect(JSONValue.string(refresh?["refresh_token"]) == "r")
    }

    @Test func parsesDeviceCodeAndTokenResponses() {
        let challenge = DeviceCodeChallenge.parse(Data(#"{"device_auth_id":"dev_1","usercode":"ABCD-EFGH","interval":"7"}"#.utf8))
        #expect(challenge == DeviceCodeChallenge(deviceAuthID: "dev_1", userCode: "ABCD-EFGH", pollInterval: 7))
        let grant = DeviceCodeGrant.parse(Data(#"{"authorization_code":"code","code_challenge":"ch","code_verifier":"ver"}"#.utf8))
        #expect(grant == DeviceCodeGrant(authorizationCode: "code", codeChallenge: "ch", codeVerifier: "ver"))
        #expect(OAuthErrorBody.parse(Data(#"{"error":"invalid_grant"}"#.utf8)).isPermanentRefreshFailure)
        #expect(!OAuthErrorBody.parse(Data(#"{"error":{"code":"server_error"}}"#.utf8)).isPermanentRefreshFailure)
        #expect(OAuthTokenResponse.parse(Data(#"{"access_token":"a","refresh_token":"r"}"#.utf8))?.refreshToken == "r")
        #expect(OAuthTokenResponse.parse(Data("{}".utf8)) == nil)
    }
}

@Suite struct RequestTests {
    @Test func encodesResponsesRequest() throws {
        let request = ResponsesRequest(
            model: "gpt-5.5",
            instructions: "Be nice",
            input: [
                ResponsesInputMessage(role: .user, content: [.inputText("Hi"), .inputImage(dataURL: "data:image/jpeg;base64,AAA")]),
                ResponsesInputMessage(role: .assistant, content: [.outputText("Hello")]),
            ],
            tools: [.webSearch(externalWebAccess: true)],
            reasoning: ResponsesReasoning(effort: "high", summary: "auto"),
            promptCacheKey: "conv-1",
            text: ResponsesTextOptions(verbosity: "medium")
        )
        let json = try #require(JSONValue.object(try request.encoded()))
        #expect(JSONValue.string(json["model"]) == "gpt-5.5")
        #expect(JSONValue.string(json["instructions"]) == "Be nice")
        #expect(JSONValue.bool(json["store"]) == false)
        #expect(JSONValue.bool(json["stream"]) == true)
        #expect(JSONValue.string(json["tool_choice"]) == "auto")
        #expect(JSONValue.string(json["prompt_cache_key"]) == "conv-1")

        let input = try #require(json["input"] as? [[String: Any]])
        #expect(JSONValue.string(input[0]["type"]) == "message")
        #expect(JSONValue.string(input[0]["role"]) == "user")
        let content = try #require(input[0]["content"] as? [[String: Any]])
        #expect(JSONValue.string(content[1]["type"]) == "input_image")
        #expect(JSONValue.string(content[1]["image_url"]) == "data:image/jpeg;base64,AAA")
        let assistant = try #require(input[1]["content"] as? [[String: Any]])
        #expect(JSONValue.string(assistant.first?["type"]) == "output_text")

        let tools = try #require(json["tools"] as? [[String: Any]])
        #expect(JSONValue.string(tools.first?["type"]) == "web_search")
        #expect(JSONValue.bool(tools.first?["external_web_access"]) == true)
        let reasoning = try #require(json["reasoning"] as? [String: Any])
        #expect(JSONValue.string(reasoning["effort"]) == "high")
        #expect(JSONValue.string(reasoning["summary"]) == "auto")
    }

    @Test func buildsInputFromHistory() {
        let image = MessageAttachment(kind: .image, storedFileName: "a.jpg", mimeType: "image/jpeg", byteCount: 3)
        let file = MessageAttachment(kind: .text, storedFileName: "b.txt", displayName: "notes.txt", mimeType: "text/plain", byteCount: 5)
        let messages = [
            ChatMessage(role: .user, text: "Look", attachments: [image, file]),
            ChatMessage(role: .assistant, text: "", status: .failed),
            ChatMessage(role: .assistant, text: "Nice"),
        ]
        let input = ResponsesInputBuilder.input(for: messages) { attachment in
            attachment.kind == .image ? .imageDataURL("data:image/jpeg;base64,AAA") : .text("hello")
        }
        #expect(input == [
            ResponsesInputMessage(role: .user, content: [
                .inputImage(dataURL: "data:image/jpeg;base64,AAA"),
                .inputText("Attached file \"notes.txt\":\n```\nhello\n```"),
                .inputText("Look"),
            ]),
            ResponsesInputMessage(role: .assistant, content: [.outputText("Nice")]),
        ])
    }

    @Test func sanitizesTitles() {
        #expect(TitlePrompt.sanitize("Title: \"Planning a trip to Lyon.\"\nextra") == "Planning a trip to Lyon")
        #expect(TitlePrompt.sanitize("  **Recette de crêpes**  ") == "Recette de crêpes")
        #expect(TitlePrompt.sanitize("\"\"") == nil)
        #expect(Conversation.fallbackTitle(from: "## How do I *sort* an array in Swift quickly and safely please?") == "How do I sort an array in Swift quickly and saf…")
    }

    @Test func conversationRoundTripsAndDecodesLeniently() throws {
        let conversation = Conversation(title: "", messages: [ChatMessage(role: .user, text: "Hello there"), ChatMessage(role: .assistant, text: "**Hi!**")])
        let encoder = JSONEncoder()
        let decoded = try JSONDecoder().decode(Conversation.self, from: try encoder.encode(conversation))
        #expect(decoded == conversation)
        #expect(decoded.summary.title == "Hello there")
        #expect(decoded.summary.preview == "Hi!")

        let minimal = try JSONDecoder().decode(ChatMessage.self, from: Data(#"{"role":"assistant","text":"x","status":"unknown-status"}"#.utf8))
        #expect(minimal.status == .complete)
        #expect(minimal.attachments.isEmpty)
    }
}

@Suite struct ModelCatalogTests {
    @Test func parsesCodexCatalog() throws {
        let json = #"{"models":[{"slug":"hidden","display_name":"Hidden","visibility":"hide","priority":0,"supported_reasoning_levels":[]},{"slug":"gpt-5.5","display_name":"GPT-5.5","description":"Fast","visibility":"list","priority":12,"default_reasoning_level":"medium","supported_reasoning_levels":[{"effort":"low","description":"Quick"},{"effort":"medium","description":"Balanced"},{"effort":"xhigh","description":"Deep"}],"support_verbosity":true,"input_modalities":["text","image"],"context_window":272000},{"slug":"gpt-6-astra","display_name":"GPT-6-Astra","visibility":"list","priority":1,"supported_reasoning_levels":[{"effort":"low","description":"x"}],"input_modalities":["text"]}]}"#
        let models = try #require(ModelCatalog.parseCodexModels(Data(json.utf8)))
        #expect(models.map(\.id) == ["gpt-6-astra", "gpt-5.5"])
        #expect(models[0].acceptsImages == false)
        #expect(models[1].summary == "Fast")
        #expect(models[1].contextWindow == 272_000)
        #expect(models[1].reasoningEfforts.map(\.effort) == ["low", "medium", "xhigh"])
        #expect(models[1].resolvedEffort(preferred: "xhigh") == "xhigh")
        #expect(models[1].resolvedEffort(preferred: "ultra") == "medium")
        #expect(models[1].lightestEffort == "low")
    }

    @Test func filtersPlatformModels() throws {
        let json = #"{"data":[{"id":"gpt-5"},{"id":"gpt-4o-2024-08-06"},{"id":"text-embedding-3-small"},{"id":"gpt-4o-mini-tts"},{"id":"o4-mini"},{"id":"gpt-4.1"},{"id":"dall-e-3"},{"id":"gpt-5-chat-latest"}]}"#
        let models = try #require(ModelCatalog.parsePlatformModels(Data(json.utf8)))
        #expect(Set(models.map(\.id)) == ["gpt-5", "o4-mini", "gpt-4.1", "gpt-5-chat-latest"])
        #expect(models.first?.id == "gpt-5")
        #expect(ModelCatalog.platformDescriptor(for: "gpt-5-chat-latest").supportsReasoning == false)
        #expect(ModelCatalog.platformDescriptor(for: "o4-mini").supportsVerbosity == false)
        #expect(ModelCatalog.platformDescriptor(for: "gpt-4.1").displayName == "GPT-4.1")
    }
}

@Suite struct ConversationGroupingTests {
    @Test func groupsByRecency() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_757_764_800) // 2025-09-13 12:00 UTC
        func summary(_ daysAgo: Double, pinned: Bool = false) -> ConversationSummary {
            ConversationSummary(id: UUID(), title: "t", createdAt: now, updatedAt: now.addingTimeInterval(-daysAgo * 86_400), isPinned: pinned, preview: "")
        }
        let sections = ConversationGrouping.sections(
            for: [summary(0.1), summary(1), summary(3), summary(20), summary(90), summary(400, pinned: true)],
            now: now,
            calendar: calendar
        )
        #expect(sections.map(\.bucket) == [.pinned, .today, .yesterday, .previous7Days, .previous30Days, .month(year: 2025, month: 6)])
    }
}
