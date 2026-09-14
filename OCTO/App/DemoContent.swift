#if OCTO_DEMO
import Foundation
import OCTOCore

/// Screens captured by `Scripts/take-screenshots.sh`, chosen with `-OCTODemoScene <name>`.
enum DemoScene: String, CaseIterable {
    case welcome
    case home
    case chat
    case sidebar
    case voice
    case settings
    case whatsNew

    static var current: DemoScene? {
        UserDefaults.standard.string(forKey: "OCTODemoScene").flatMap(DemoScene.init(rawValue:))
    }
}

/// Fake account and chats for the README screenshots. Only compiled into screenshot builds.
@MainActor
enum DemoContent {
    static let featuredConversationID = UUID(uuidString: "0C70C0DE-0000-4000-8000-000000000001")!
    private static let projectID = "g-p-0c70c0de"

    static func prepare(_ scene: DemoScene, app: AppModel) {
        guard scene != .welcome else {
            app.auth.useDemoAccount(nil)
            return
        }
        app.auth.useDemoAccount(Account(email: "gabriel@example.com", planType: "plus", userID: "user-demo"))
        app.account.useDemo(AccountSnapshot(
            profile: AccountProfile(userID: "user-demo", name: "Gabriel", email: "gabriel@example.com"),
            settings: AccountSettings(referencesSavedMemories: true, referencesChatHistory: true, trainingAllowed: false),
            instructions: CustomInstructions(
                nickname: "Gabriel",
                occupation: localized("Student", "Étudiant"),
                aboutUser: localized("I'm learning Swift and SwiftUI.", "J'apprends Swift et SwiftUI."),
                responseStyle: localized("Be concise and give examples.", "Sois concis et donne des exemples."),
                personality: "default"
            ),
            personalities: [
                PersonalityOption(key: "default", label: localized("Default", "Par défaut"), summary: localized("Preset style and tone", "Style et ton prédéfinis")),
                PersonalityOption(key: "professional", label: localized("Professional", "Professionnel"), summary: localized("Polished and precise", "Courtois et précis")),
            ],
            traits: [],
            memories: MemoriesSnapshot(memories: [SavedMemory(id: "demo-memory", content: localized("Is learning Swift", "Apprend Swift"))]),
            trainingAllowed: false
        ))
        app.store.useDemoProjects([
            ChatProject(id: projectID, name: localized("School", "Cours"), iconName: "graduation-cap", colorHex: "#0285FF"),
        ])
        for conversation in conversations(now: Date()) {
            app.store.save(conversation)
        }
        if scene == .whatsNew {
            app.whatsNew = ReleaseNotes.current
        }
    }

    /// Tells `take-screenshots.sh` that the scene is on screen (it watches the app's tmp folder).
    static func markReady() {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("OCTODemoReady")
        FileManager.default.createFile(atPath: marker.path, contents: Data())
    }

    private static var usesFrench: Bool {
        Locale.preferredLanguages.first?.hasPrefix("fr") ?? false
    }

    private static func localized(_ english: String, _ french: String) -> String {
        usesFrench ? french : english
    }

    private static func conversations(now: Date) -> [Conversation] {
        let model = ModelCatalog.chatGPTFallback[0]

        func chat(
            _ id: UUID = UUID(),
            title: String,
            hoursAgo: Double,
            pinned: Bool = false,
            fromAccount: Bool = true,
            inProject: Bool = false,
            question: String,
            answer: String,
            thinking: TimeInterval? = nil
        ) -> Conversation {
            let date = now.addingTimeInterval(-hoursAgo * 3_600)
            let remoteID = fromAccount ? id.uuidString.lowercased() : nil
            return Conversation(
                id: id,
                title: title,
                createdAt: date,
                updatedAt: date,
                isPinned: pinned,
                modelID: model.id,
                reasoningEffort: model.defaultReasoningEffort,
                messages: [
                    ChatMessage(role: .user, text: question, createdAt: date, remoteID: remoteID.map { "\($0)-question" }),
                    ChatMessage(role: .assistant, text: answer, reasoningDuration: thinking, modelID: model.id, createdAt: date, remoteID: remoteID.map { "\($0)-answer" }),
                ],
                remoteID: remoteID,
                projectID: inProject ? projectID : nil,
                remoteUpdatedAt: fromAccount ? date : nil
            )
        }

        return [
            chat(
                featuredConversationID,
                title: localized("Networking with async/await", "Requête réseau en Swift"),
                hoursAgo: 0.05,
                fromAccount: false,
                question: localized("How do I make a network request in Swift with async/await?", "Comment faire une requête réseau en Swift avec async/await ?"),
                answer: localized(featuredAnswerEnglish, featuredAnswerFrench),
                thinking: 7
            ),
            chat(
                title: localized("Name ideas for my app", "Idées de nom pour mon app"),
                hoursAgo: 2,
                question: localized("Give me name ideas for a private AI chat app", "Donne-moi des idées de nom pour une app de chat IA privée"),
                answer: localized("Here are a few ideas: **Octo**, **Nook**, **Hush** and **Kite**.", "Voici quelques idées : **Octo**, **Nook**, **Hush** et **Kite**.")
            ),
            chat(
                title: localized("Authentic carbonara", "Carbonara authentique"),
                hoursAgo: 5,
                question: localized("What's the real carbonara recipe?", "Quelle est la vraie recette de la carbonara ?"),
                answer: localized("Guanciale, egg yolks, pecorino romano and black pepper. No cream!", "Guanciale, jaunes d'œufs, pecorino romano et poivre noir. Pas de crème !")
            ),
            chat(
                title: localized("Weekend in Lisbon", "Week-end à Lisbonne"),
                hoursAgo: 30,
                pinned: true,
                question: localized("Plan a 3-day trip to Lisbon", "Organise-moi 3 jours à Lisbonne"),
                answer: localized("Day 1: Alfama and the castle. Day 2: Belém. Day 3: Sintra.", "Jour 1 : l'Alfama et le château. Jour 2 : Belém. Jour 3 : Sintra.")
            ),
            chat(
                title: localized("Summary of The Plague", "Résumé de La Peste"),
                hoursAgo: 60,
                inProject: true,
                question: localized("Summarize The Plague by Camus", "Résume La Peste de Camus"),
                answer: localized("In Oran, a plague epidemic isolates the city…", "À Oran, une épidémie de peste isole la ville…")
            ),
            chat(
                title: localized("Python script to rename photos", "Script Python pour renommer des photos"),
                hoursAgo: 90,
                question: localized("Write a script that renames my photos by date", "Écris un script qui renomme mes photos par date"),
                answer: "```python\nimport os\n```"
            ),
            chat(
                title: localized("Job interview prep", "Préparer un entretien"),
                hoursAgo: 200,
                question: localized("Help me prepare for a job interview", "Aide-moi à préparer un entretien d'embauche"),
                answer: localized("Let's start with the questions you're likely to get.", "Commençons par les questions qu'on risque de te poser.")
            ),
            chat(
                title: localized("Black holes explained", "Les trous noirs expliqués"),
                hoursAgo: 400,
                inProject: true,
                question: localized("Explain black holes simply", "Explique-moi simplement les trous noirs"),
                answer: localized("A black hole is a region where gravity is so strong that nothing escapes.", "Un trou noir est une région où la gravité est si forte que rien ne s'en échappe.")
            ),
            chat(
                title: localized("Monthly budget", "Budget mensuel"),
                hoursAgo: 1_000,
                question: localized("Help me build a monthly budget", "Aide-moi à faire un budget mensuel"),
                answer: localized("Start by listing your fixed expenses.", "Commence par lister tes dépenses fixes.")
            ),
        ]
    }

    private static let featuredAnswerFrench = #"""
    Avec **async/await**, une requête réseau tient en quelques lignes grâce à `URLSession` :

    ```swift
    func fetchUser(id: Int) async throws -> User {
        let url = URL(string: "https://api.example.com/users/\(id)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(User.self, from: data)
    }
    ```

    ### À retenir

    - `await` suspend la fonction sans bloquer l'interface.
    - `try` fait remonter les erreurs réseau et de décodage.
    - Appelle-la depuis une `Task` dans ta vue SwiftUI.
    """#

    private static let featuredAnswerEnglish = #"""
    With **async/await**, a network request takes just a few lines with `URLSession`:

    ```swift
    func fetchUser(id: Int) async throws -> User {
        let url = URL(string: "https://api.example.com/users/\(id)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(User.self, from: data)
    }
    ```

    ### Key points

    - `await` suspends the function without blocking the UI.
    - `try` propagates networking and decoding errors.
    - Call it from a `Task` in your SwiftUI view.
    """#
}
#endif
