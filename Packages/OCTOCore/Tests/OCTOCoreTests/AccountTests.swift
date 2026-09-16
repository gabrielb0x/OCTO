import Foundation
import Testing
@testable import OCTOCore

@Suite struct AccountAPITests {
    @Test func buildsAccountRequests() throws {
        #expect(ChatGPTAccountAPI.profileURL.absoluteString == "https://chatgpt.com/backend-api/me")
        #expect(ChatGPTAccountAPI.settingsURL.absoluteString == "https://chatgpt.com/backend-api/settings/user")
        #expect(ChatGPTAccountAPI.memoriesURL.absoluteString == "https://chatgpt.com/backend-api/memories?include_memory_entries=true")
        #expect(ChatGPTAccountAPI.conversationsURL(offset: 28, limit: 28).absoluteString == "https://chatgpt.com/backend-api/conversations?offset=28&limit=28&order=updated&is_archived=false")
        #expect(ChatGPTAccountAPI.conversationURL(id: "6aa78bc8-756c-83eb-b946-e17ad6461b0a").absoluteString == "https://chatgpt.com/backend-api/conversation/6aa78bc8-756c-83eb-b946-e17ad6461b0a")
        #expect(ChatGPTAccountAPI.conversationURL(id: "../me").absoluteString == "https://chatgpt.com/backend-api/conversation/..%2Fme")
        #expect(ChatGPTAccountAPI.memoryURL(id: "mem-1").absoluteString == "https://chatgpt.com/backend-api/memories/mem-1")
        #expect(ChatGPTAccountAPI.memoryURL(id: "../me").absoluteString == "https://chatgpt.com/backend-api/memories/..%2Fme")
        #expect(ChatGPTAccountAPI.projectConversationsURL(projectID: "g-p-1", cursor: nil).absoluteString == "https://chatgpt.com/backend-api/gizmos/g-p-1/conversations?cursor=0&limit=50&owned_only=true")

        let headers = ChatGPTAccountAPI.headers(accessToken: "token", accountID: "account", userAgent: "agent", language: "fr-FR")
        #expect(headers["Authorization"] == "Bearer token")
        #expect(headers["ChatGPT-Account-ID"] == "account")
        #expect(headers["OAI-Language"] == "fr-FR")
        #expect(headers["Accept"] == "application/json")

        let body = try #require(JSONValue.object(ChatGPTAccountAPI.conversationUpdateBody(title: "Trip", isVisible: false)))
        #expect(JSONValue.string(body["title"]) == "Trip")
        #expect(JSONValue.bool(body["is_visible"]) == false)
        #expect(body["is_archived"] == nil)
    }

    @Test func parsesDatesAndIdentifiers() throws {
        let microseconds = try #require(FlexibleDate.parse("2026-09-14T05:53:13.163727Z"))
        #expect(abs(microseconds.timeIntervalSince1970 - 1_789_365_193.163727) < 0.0001)
        let offset = try #require(FlexibleDate.parse("2026-05-16T10:51:41.5+02:00"))
        #expect(abs(offset.timeIntervalSince1970 - 1_778_921_501.5) < 0.0001)
        #expect(FlexibleDate.parse(1_757_764_800.5) == Date(timeIntervalSince1970: 1_757_764_800.5))
        #expect(FlexibleDate.parse("not a date") == nil)
        #expect(FlexibleDate.parse(NSNull()) == nil)

        #expect(RemoteIdentifier.localID(for: "6aa78bc8-756c-83eb-b946-e17ad6461b0a") == UUID(uuidString: "6AA78BC8-756C-83EB-B946-E17AD6461B0A"))
        #expect(RemoteIdentifier.localID(for: "client-created-root") == RemoteIdentifier.localID(for: "client-created-root"))
        #expect(RemoteIdentifier.localID(for: "client-created-root") != RemoteIdentifier.localID(for: "client-created-rooT"))
    }

    @Test func parsesProfileSettingsAndInstructions() throws {
        let profile = try #require(AccountProfile.parse(Data(#"{"object":"user","id":"user-1","email":"me@example.com","name":"Gabriel ","picture":"https://chatgpt.com/backend-api/estuary/public_content/enc/abc","created":1674378627}"#.utf8)))
        #expect(profile == AccountProfile(userID: "user-1", name: "Gabriel", email: "me@example.com", pictureURL: URL(string: "https://chatgpt.com/backend-api/estuary/public_content/enc/abc"), createdAt: Date(timeIntervalSince1970: 1_674_378_627)))

        let withPhone = try #require(AccountProfile.parse(Data(#"{"id":"user-2","email":"me@example.com","phone_number":" +33600000000 ","mfa_flag_enabled":false}"#.utf8)))
        #expect(withPhone.phoneNumber == "+33600000000")
        #expect(withPhone.mfaEnabled == false)
        #expect(AccountProfile.parse(Data(#"{"id":"user-3","phone_number":""}"#.utf8))?.phoneNumber == nil)

        let settings = try #require(AccountSettings.parse(Data(#"{"settings":{"sunshine":true,"moonshine":false,"training_allowed":false,"voice_training_allowed":true,"video_training_allowed":false,"codex_training_allowed":true,"codex_training_allowed_v2":false,"voice_name":"ember","voice_main_language":"fr"}}"#.utf8)))
        #expect(settings.referencesSavedMemories == true)
        #expect(settings.referencesChatHistory == false)
        #expect(settings.trainingAllowed == false)
        #expect(settings.voiceTrainingAllowed == true)
        #expect(settings.videoTrainingAllowed == false)
        #expect(settings.codexTrainingAllowed == false)
        #expect(settings.voiceName == "ember")
        var changed = settings
        changed[.voiceTrainingAllowed] = false
        #expect(changed.voiceTrainingAllowed == false)
        #expect(changed[.trainingAllowed] == false)
        #expect(ChatGPTAccountAPI.accountUserSettingURL(.trainingAllowed, value: false).absoluteString == "https://chatgpt.com/backend-api/settings/account_user_setting?feature=training_allowed&value=false")
        #expect(ChatGPTAccountAPI.accountUserSettingURL(.codexTrainingAllowed, value: true).absoluteString == "https://chatgpt.com/backend-api/settings/account_user_setting?feature=codex_training_allowed_v2&value=true")
        // "permitted" is the account's policy, not the choice made in Data controls.
        #expect(TrainingPolicy.parse(Data(#"{"auth_user_id":"user-1","data_usage_for_training":"permitted"}"#.utf8)) == true)

        let json = #"{"object":"user_system_message_detail","about_user_message":"I study networks","about_model_message":"Be concise","name_user_message":"Gabriel","role_user_message":"Student","traits_model_message":"Be concise","other_user_message":"I study networks","personality_type_selection":"cynic","disabled_tools":[],"enabled":true,"traits_enabled":true,"personality_traits":{"emoji":"more","warm":"less"}}"#
        let instructions = try #require(CustomInstructions.parse(Data(json.utf8)))
        #expect(instructions.nickname == "Gabriel")
        #expect(instructions.occupation == "Student")
        #expect(instructions.aboutUser == "I study networks")
        #expect(instructions.responseStyle == "Be concise")
        #expect(instructions.personality == "cynic")
        #expect(instructions.traits == ["emoji": "more", "warm": "less"])

        var edited = instructions
        edited.nickname = "Gab"
        edited.traits["emoji"] = "default"
        #expect(edited != instructions)
        let body = try #require(JSONValue.object(edited.requestBody()))
        #expect(JSONValue.string(body["name_user_message"]) == "Gab")
        #expect(JSONValue.string(body["about_model_message"]) == "Be concise")
        #expect(JSONValue.bool(body["traits_enabled"]) == true)
        #expect(body["object"] == nil)
        let traits = try #require(body["personality_traits"] as? [String: Any])
        #expect(JSONValue.string(traits["emoji"]) == "default")
    }

    @Test func parsesFeatureLimitsFromConversationInit() throws {
        let json = #"""
        {"type":"conversation_detail_metadata","banner_info":null,
         "blocked_features":[{"name":"file_upload","resets_after":"2026-09-16T07:46:12.855760+00:00","description":"You've hit your file limit."}],
         "model_limits":[{"model_slug":"gpt-5-6","using_default_model_slug":"gpt-5-6","resets_after":"2026-09-15T17:18:03.131140+00:00"}],
         "limits_progress":[
           {"feature_name":"deep_research","remaining":5,"reset_after":"2026-10-15T16:42:07.853427+00:00"},
           {"feature_name":"file_upload","remaining":0,"reset_after":"2026-09-16T07:46:12.853615+00:00"},
           {"feature_name":"image_gen","remaining":3,"reset_after":"2026-09-16T16:42:07.853628+00:00"}
         ],
         "default_model_slug":"auto","file_attachment_limits":{"max_size_mb":512}}
        """#
        let limits = try #require(FeatureLimits.parse(Data(json.utf8)))
        #expect(limits.defaultModelSlug == "auto")
        #expect(limits.maxAttachmentMB == 512)
        #expect(limits.features.map(\.feature) == ["deep_research", "file_upload", "image_gen"])

        let research = try #require(limits.features.first)
        #expect(research.remaining == 5)
        #expect(research.isBlocked == false)
        #expect(research.resetsAt != nil)

        let fileUpload = limits.features[1]
        #expect(fileUpload.remaining == 0)
        #expect(fileUpload.isBlocked)
        #expect(fileUpload.message == "You've hit your file limit.")

        #expect(FeatureLimits.parse(Data(#"{"foo":1}"#.utf8)) == nil)

        let body = try #require(JSONValue.object(ChatGPTAccountAPI.conversationInitBody(timezone: "Europe/Paris", offsetMinutes: -120)))
        #expect(body["timezone"] as? String == "Europe/Paris")
        #expect(JSONValue.int(body["timezone_offset_min"]) == -120)
        #expect(body["conversation_id"] is NSNull)
        #expect(ChatGPTAccountAPI.conversationInitURL.absoluteString == "https://chatgpt.com/backend-api/conversation/init")
    }

    @Test func parsesCheckoutPricing() throws {
        let json = #"""
        {"country_code":"FR","currency_config":{
          "free":{"month":{"tax":"inclusive","amount":0.0}},
          "go":{"month":{"amount":8.0,"tax":"inclusive","psp_override":{"amount":6.67,"tax":"exclusive"}}},
          "plus":{"month":{"amount":23.0,"tax":"inclusive"},"year":{"amount":19.17,"tax":"inclusive"}},
          "pro":{"month":{"amount":229.0,"tax":"inclusive"}},
          "business":{"month":{"amount":26.0,"tax":"exclusive"}},
          "symbol_code":"EUR","symbol":"€","tax_percent":20.0,"minor_unit_exponent":2}}
        """#
        let pricing = try #require(CheckoutPricing.parse(Data(json.utf8)))
        #expect(pricing.countryCode == "FR")
        #expect(pricing.currencyCode == "EUR")
        #expect(pricing.taxPercent == 20)
        #expect(pricing.plan("plus")?.monthly?.amount == 23)
        #expect(pricing.plan("plus")?.monthly?.includesTax == true)
        #expect(pricing.plan("plus")?.yearly?.amount == 19.17)
        #expect(pricing.plan("business")?.monthly?.includesTax == false)
        // Go is sold by the month only: chained on its own so `yearly` isn't a double optional.
        let go = try #require(pricing.plan("go"))
        #expect(go.monthly?.amount == 8)
        #expect(go.yearly == nil)
        // The free plan costs nothing, so it isn't a plan to buy; the currency keys aren't plans either.
        #expect(pricing.plan("free") == nil)
        #expect(pricing.plan("symbol_code") == nil)
        #expect(pricing.personalPlans.map(\.key) == ["go", "plus", "pro"])
        // Cheapest first, whatever order the account listed them in.
        #expect(pricing.plans.map(\.key) == ["go", "plus", "business", "pro"])
        #expect(CheckoutPricing.parse(Data(#"{"country_code":"FR"}"#.utf8)) == nil)

        #expect(ChatGPTAccountAPI.checkoutPricingURL(countryCode: "fr").absoluteString == "https://chatgpt.com/backend-api/checkout_pricing_config/configs/FR")
        // An unknown or unusable region asks for the prices ChatGPT shows in the United States.
        #expect(ChatGPTAccountAPI.checkoutPricingURL(countryCode: "").absoluteString.hasSuffix("/configs/US"))
        #expect(ChatGPTAccountAPI.checkoutPricingURL(countryCode: "../me").absoluteString.hasSuffix("/configs/US"))
    }

    @Test func showsSubscriptionDatesOnlyWhileActive() throws {
        // A Plus subscription that ended: the free account still carries its dates.
        let json = #"{"accounts":{"acc":{"account":{"plan_type":"free","structure":"personal"},"entitlement":{"has_active_subscription":false,"subscription_plan":"chatgptplusplan","expires_at":"2026-08-12T22:18:08+00:00","renews_at":null,"cancels_at":"2026-08-12T16:18:08+00:00","billing_period":"monthly"},"last_active_subscription":{"purchase_origin_platform":"chatgpt_web","will_renew":false}}},"account_ordering":["acc"]}"#
        let ended = try #require(AccountSubscription.parse(Data(json.utf8), accountID: "acc"))
        #expect(ended.planType == "free")
        #expect(ended.hasActiveSubscription == false)
        #expect(ended.expiresAt != nil)
        #expect(ended.cancelsAt != nil)
        #expect(ended.renewalDate == nil)
        #expect(ended.endDate == nil)

        let renewing = AccountSubscription(planType: "plus", hasActiveSubscription: true, expiresAt: Date(timeIntervalSince1970: 100), renewsAt: Date(timeIntervalSince1970: 200), willRenew: true)
        #expect(renewing.renewalDate == Date(timeIntervalSince1970: 200))
        #expect(renewing.endDate == nil)

        let cancelled = AccountSubscription(planType: "plus", hasActiveSubscription: true, expiresAt: Date(timeIntervalSince1970: 300), cancelsAt: Date(timeIntervalSince1970: 250), willRenew: false)
        #expect(cancelled.renewalDate == nil)
        #expect(cancelled.endDate == Date(timeIntervalSince1970: 300))
    }

    @Test func readsTheAgeStatus() throws {
        let teen = try #require(AgeStatus.parse(Data(#"{"is_adult":false,"has_verified_age_or_dob":false,"age_is_known":true,"is_u18_model_policy_enabled":true,"show_age_verification_setting":true,"age_status":"under_18"}"#.utf8)))
        #expect(teen.standing == .underEighteen)
        #expect(teen.offersVerification == true)
        #expect(teen.status == "under_18")
        #expect(AgeStatus.parse(Data(#"{"is_adult":true,"has_verified_age_or_dob":true}"#.utf8))?.standing == .verifiedAdult)
        #expect(AgeStatus.parse(Data(#"{"is_adult":true,"has_verified_age_or_dob":false}"#.utf8))?.standing == .adult)
        #expect(AgeStatus.parse(Data(#"{"age_status":null}"#.utf8))?.standing == .unknown)
        #expect(AgeStatus.parse(Data(#"{"foo":1}"#.utf8)) == nil)
        #expect(ChatGPTAccountAPI.ageStatusURL.absoluteString == "https://chatgpt.com/backend-api/settings/is_adult")
    }

    @Test func parsesPersonalityCatalogAndMemories() throws {
        let types = try #require(PersonalityCatalog.parseTypes(Data(#"[{"key":"default","label":"Default","description":"Preset style and tone","deprecated":false},{"key":"old","label":"Old","deprecated":true},{"key":"cynic","label":"Cynical","description":"Critical and sarcastic"}]"#.utf8)))
        #expect(types.map(\.key) == ["default", "cynic"])
        #expect(types[1].summary == "Critical and sarcastic")

        let traits = try #require(PersonalityCatalog.parseTraits(Data(#"{"trait_types":[{"key":"warm","label":"Warm","deprecated":false,"levels":[{"key":"more","label":"Warmer","option_label":"More","description":"Friendlier"},{"key":"default","label":"","option_label":"Default"},{"key":"less","label":"Less warm","option_label":""}]}]}"#.utf8)))
        #expect(traits.first?.label == "Warm")
        #expect(traits.first?.levels.map(\.label) == ["More", "Default", "Less warm"])

        let memories = try #require(MemoriesSnapshot.parse(Data(#"{"memories":[{"id":"m1","content":"Likes Swift","updated_at":"2026-01-02T10:00:00Z"},{"id":"m2","content":"  "}],"memory_max_tokens":2000,"memory_num_tokens":120}"#.utf8)))
        #expect(memories.memories.map(\.content) == ["Likes Swift"])
        #expect(memories.maxTokens == 2_000)
        #expect(memories.usedTokens == 120)
    }
}

@Suite struct AccountChatTests {
    @Test func parsesChatListsAndProjects() throws {
        let page = try #require(RemoteConversationPage.parse(Data(#"{"items":[{"id":"6aa78bc8-756c-83eb-b946-e17ad6461b0a","title":" Kitten ","create_time":"2026-09-14T05:53:13.163727Z","update_time":"2026-09-14T06:06:19.113203Z","pinned_time":null,"gizmo_id":null,"is_archived":false,"is_starred":null},{"title":"no id"}],"total":2,"limit":28,"offset":0}"#.utf8)))
        #expect(page.total == 2)
        #expect(page.items.count == 1)
        #expect(page.items.first?.title == "Kitten")
        #expect(page.items.first?.isPinned == false)
        #expect(page.items.first?.projectID == nil)

        let projects = try #require(RemoteProjectList.parse(Data(##"{"items":[{"gizmo":{"gizmo":{"id":"g-p-1","display":{"name":"School","emoji":"graduation-cap","theme":"#0285FF"}}},"conversations":{"items":[{"id":"c1","title":"Homework","create_time":"2026-07-26T09:02:12Z","update_time":"2026-09-11T12:00:57Z","gizmo_id":"g-p-1","pinned_time":"2026-09-12T00:00:00Z"}],"cursor":5}}],"cursor":null}"##.utf8)))
        let project = try #require(projects.first)
        #expect(project.name == "School")
        #expect(project.iconName == "graduation-cap")
        #expect(project.colorHex == "#0285FF")
        #expect(project.conversations.first?.projectID == "g-p-1")
        #expect(project.conversations.first?.isPinned == true)
        #expect(project.conversationsCursor == "5")
    }

    @Test func rebuildsTheVisibleBranchOfAChat() throws {
        let json = #"""
        {"title":"Voyage à Lyon","create_time":1757764800.5,"update_time":1757768400.25,"conversation_id":"6aa78bc8-756c-83eb-b946-e17ad6461b0a","current_node":"n6","gizmo_id":null,
         "mapping":{
          "root":{"id":"root","message":null,"parent":null,"children":["n0"]},
          "n0":{"id":"n0","message":{"id":"m0","author":{"role":"system"},"content":{"content_type":"text","parts":[""]},"metadata":{"is_visually_hidden_from_conversation":true}},"parent":"root","children":["n1"]},
          "n1":{"id":"n1","message":{"id":"m1","author":{"role":"user"},"create_time":1757764801,"content":{"content_type":"multimodal_text","parts":[{"content_type":"image_asset_pointer","asset_pointer":"sediment://file_1"},"Que voir à Lyon ?"]},"metadata":{"attachments":[{"id":"file_1","name":"photo.jpg","mime_type":"image/jpeg"},{"id":"file_2","name":"notes.pdf","mime_type":"application/pdf"}]},"recipient":"all"},"parent":"n0","children":["n2","x2"]},
          "x2":{"id":"x2","message":{"id":"old","author":{"role":"assistant"},"content":{"content_type":"text","parts":["Old branch"]},"recipient":"all"},"parent":"n1","children":[]},
          "n2":{"id":"n2","message":{"id":"m2","author":{"role":"assistant"},"content":{"content_type":"thoughts","thoughts":[{"summary":"Planning","content":"Listing sights"}]},"metadata":{},"recipient":"all"},"parent":"n1","children":["n3"]},
          "n3":{"id":"n3","message":{"id":"m3","author":{"role":"assistant"},"content":{"content_type":"reasoning_recap","content":"Thought for 12s"},"metadata":{"finished_duration_sec":12},"recipient":"all"},"parent":"n2","children":["n4"]},
          "n4":{"id":"n4","message":{"id":"m4","author":{"role":"assistant"},"content":{"content_type":"code","text":"search(\"Lyon\")"},"recipient":"web.run"},"parent":"n3","children":["n5"]},
          "n5":{"id":"n5","message":{"id":"m5","author":{"role":"tool","name":"web.run"},"content":{"content_type":"text","parts":["results"]},"recipient":"all"},"parent":"n4","children":["n6"]},
          "n6":{"id":"n6","message":{"id":"m6","author":{"role":"assistant"},"create_time":1757764830,"content":{"content_type":"text","parts":["Va voir la entity[\"place\",\"Basilique de Fourvière\"] et le Vieux Lyon. citeturn0search0"]},"metadata":{"content_references":[{"matched_text":"citeturn0search0","type":"grouped_webpages","items":[{"title":"Lyon Tourisme","url":"https://www.visiterlyon.com"}]}]},"recipient":"all"},"parent":"n5","children":[]}
         }}
        """#
        let conversation = try #require(RemoteConversationParser.parse(Data(json.utf8), id: "fallback"))
        #expect(conversation.id == "6aa78bc8-756c-83eb-b946-e17ad6461b0a")
        #expect(conversation.title == "Voyage à Lyon")
        #expect(conversation.updatedAt == Date(timeIntervalSince1970: 1_757_768_400.25))
        #expect(conversation.messages.count == 2)

        let question = try #require(conversation.messages.first)
        #expect(question.role == .user)
        #expect(question.text == "Que voir à Lyon ?")
        #expect(question.imageCount == 1)
        #expect(question.fileNames == ["notes.pdf"])

        let answer = try #require(conversation.messages.last)
        #expect(answer.id == "m2")
        #expect(answer.role == .assistant)
        #expect(answer.text == "Va voir la Basilique de Fourvière et le Vieux Lyon.")
        #expect(answer.reasoning == "**Planning**\n\nListing sights")
        #expect(answer.reasoningDuration == 12)
        #expect(answer.citations == [Citation(url: "https://www.visiterlyon.com", title: "Lyon Tourisme")])

        // Without a current node, the newest branch from the root is followed.
        var object = try #require(JSONValue.object(Data(json.utf8)))
        object["current_node"] = NSNull()
        let withoutCurrent = try #require(RemoteConversationParser.parse(try JSONSerialization.data(withJSONObject: object), id: "fallback"))
        #expect(withoutCurrent.messages.last?.text == "Old branch")
    }

    @Test func cleansReferenceMarkers() {
        let text = "Paris is the capital of \u{E200}entity\u{E202}[\"country\",\"France\"]\u{E201}. \u{E200}cite\u{E202}turn0search0\u{E201} Old style【3†source】."
        let references: [[String: Any]] = [[
            "matched_text": "\u{E200}cite\u{E202}turn0search0\u{E201}",
            "type": "grouped_webpages",
            "items": [["title": "Wiki", "url": "https://fr.wikipedia.org/wiki/Paris"]],
        ]]
        let result = CitationCleaner.clean(text, references: references)
        #expect(result.text == "Paris is the capital of France. Old style.")
        #expect(result.citations == [Citation(url: "https://fr.wikipedia.org/wiki/Paris", title: "Wiki")])
        #expect(CitationCleaner.clean("```\n  indented\n```", references: []).text == "```\n  indented\n```")
    }

    @Test func mergesTheAccountCopyWithTurnsWrittenInOCTO() throws {
        let remote = RemoteConversation(
            id: "6aa78bc8-756c-83eb-b946-e17ad6461b0a",
            title: "Lyon",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            messages: [
                RemoteMessage(id: "m1", role: .user, text: "Hi", createdAt: Date(timeIntervalSince1970: 100)),
                RemoteMessage(id: "m2", role: .assistant, text: "Hello", imageCount: 1, createdAt: Date(timeIntervalSince1970: 150)),
            ]
        )
        let first = AccountChatMapper.conversation(from: remote, merging: nil)
        #expect(first.id == UUID(uuidString: "6aa78bc8-756c-83eb-b946-e17ad6461b0a"))
        #expect(first.isAccountChat)
        #expect(first.messages.map(\.remoteID) == ["m1", "m2"])
        #expect(first.messages[1].attachments.first?.isStoredOnDevice == false)
        #expect(first.remoteUpdatedAt == Date(timeIntervalSince1970: 200))

        var continued = first
        continued.isPinned = true
        continued.messages.append(ChatMessage(role: .user, text: "More", createdAt: Date(timeIntervalSince1970: 300)))
        continued.updatedAt = Date(timeIntervalSince1970: 300)

        var newer = remote
        newer.title = "Lyon trip"
        newer.messages[1].text = "Hello!"
        let merged = AccountChatMapper.conversation(from: newer, merging: continued)
        #expect(merged.title == "Lyon trip")
        #expect(merged.isPinned)
        #expect(merged.messages.map(\.text) == ["Hi", "Hello!", "More"])
        #expect(merged.messages[0].id == first.messages[0].id)
        #expect(merged.updatedAt == Date(timeIntervalSince1970: 300))

        let existing = ConversationSummary(id: UUID(), title: "Kept", createdAt: Date(timeIntervalSince1970: 10), updatedAt: Date(timeIntervalSince1970: 80), isPinned: true, preview: "p")
        let summary = AccountChatMapper.summary(from: RemoteConversationSummary(id: "c1", title: "", updatedAt: Date(timeIntervalSince1970: 50)), existing: existing)
        #expect(summary.id == existing.id)
        #expect(summary.title == "Kept")
        #expect(summary.updatedAt == Date(timeIntervalSince1970: 80))
        #expect(summary.remoteID == "c1")
        #expect(summary.remoteUpdatedAt == Date(timeIntervalSince1970: 50))
        #expect(summary.isPinned)

        let decoded = try JSONDecoder().decode(Conversation.self, from: try JSONEncoder().encode(merged))
        #expect(decoded == merged)
    }
}
