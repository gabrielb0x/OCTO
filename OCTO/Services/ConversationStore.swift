import Foundation
import Observation
import OCTOCore

/// Content picked in the composer, kept in memory until the message is sent.
struct PendingAttachment: Identifiable, Equatable {
    enum Content: Equatable {
        case image(Data)
        case text(String)
    }

    let id = UUID()
    var name: String
    var content: Content
}

/// A ChatGPT project, listed in the sidebar with its chats.
struct ChatProject: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var iconName: String?
    var colorHex: String?
}

/// Space used by OCTO on the device.
struct StorageUsage: Equatable, Sendable {
    var chatsBytes: Int64 = 0
    var chatFiles = 0
    var attachmentsBytes: Int64 = 0
    var attachmentFiles = 0
    var accountBytes: Int64 = 0

    var totalBytes: Int64 {
        chatsBytes + attachmentsBytes + accountBytes
    }
}

/// JSON files in Application Support. Writes happen on a serial background queue.
final class ConversationFiles: @unchecked Sendable {
    let rootDirectory: URL
    let conversationsDirectory: URL
    let attachmentsDirectory: URL
    private let queue = DispatchQueue(label: "com.gabrielb0x.octo.storage", qos: .utility)

    convenience init(folderName: String = AccountStorage.folderName, startEmpty: Bool = false) {
        self.init(directory: AccountStorage.root(folderName: folderName), startEmpty: startEmpty)
    }

    /// The chats of one account, in that account's own folder.
    init(directory root: URL, startEmpty: Bool = false) {
        let fileManager = FileManager.default
        if startEmpty {
            try? fileManager.removeItem(at: root)
        }
        rootDirectory = root
        conversationsDirectory = root.appendingPathComponent("Conversations", isDirectory: true)
        attachmentsDirectory = root.appendingPathComponent("Attachments", isDirectory: true)
        try? fileManager.createDirectory(at: conversationsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
    }

    var indexURL: URL {
        conversationsDirectory.appendingPathComponent("index.json")
    }

    private var projectsURL: URL {
        conversationsDirectory.appendingPathComponent("projects.json")
    }

    private func fileURL(for id: UUID) -> URL {
        conversationsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    /// nil for names that don't point to a file inside the attachments folder,
    /// such as the placeholders of attachments that stayed in the ChatGPT account.
    func attachmentURL(_ name: String) -> URL? {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return nil }
        return attachmentsDirectory.appendingPathComponent(name)
    }

    func loadIndex() -> [ConversationSummary]? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        return try? JSONDecoder().decode([ConversationSummary].self, from: data)
    }

    func loadProjects() -> [ChatProject] {
        guard let data = try? Data(contentsOf: projectsURL) else { return [] }
        return (try? JSONDecoder().decode([ChatProject].self, from: data)) ?? []
    }

    func loadConversation(_ id: UUID) -> Conversation? {
        guard let data = try? Data(contentsOf: fileURL(for: id)) else { return nil }
        return try? JSONDecoder().decode(Conversation.self, from: data)
    }

    func conversationIDs() -> [UUID] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: conversationsDirectory, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url in
            url.pathExtension == "json" ? UUID(uuidString: url.deletingPathExtension().lastPathComponent) : nil
        }
    }

    func write(_ conversation: Conversation?, index: [ConversationSummary]) {
        queue.async { [self] in
            let encoder = JSONEncoder()
            if let conversation, let data = try? encoder.encode(conversation) {
                try? data.write(to: fileURL(for: conversation.id), options: [.atomic, .completeFileProtectionUnlessOpen])
            }
            if let data = try? encoder.encode(index) {
                try? data.write(to: indexURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            }
        }
    }

    func writeProjects(_ projects: [ChatProject]) {
        queue.async { [self] in
            if let data = try? JSONEncoder().encode(projects) {
                try? data.write(to: projectsURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            }
        }
    }

    func delete(_ ids: [UUID], attachmentNames: [String], index: [ConversationSummary]) {
        queue.async { [self] in
            for id in ids {
                try? FileManager.default.removeItem(at: fileURL(for: id))
            }
            for name in attachmentNames {
                if let url = attachmentURL(name) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            if let data = try? JSONEncoder().encode(index) {
                try? data.write(to: indexURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            }
        }
    }

    /// Removes the message files of chats that stay listed in the index.
    func deleteConversationFiles(_ ids: [UUID]) {
        queue.async { [self] in
            for id in ids {
                try? FileManager.default.removeItem(at: fileURL(for: id))
            }
        }
    }

    func deleteEverything() {
        queue.async { [self] in
            for directory in [conversationsDirectory, attachmentsDirectory] {
                let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
                for url in urls {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    func saveAttachment(_ data: Data, fileExtension: String) -> String? {
        let name = "\(UUID().uuidString).\(fileExtension)"
        do {
            try data.write(to: attachmentsDirectory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUnlessOpen])
            return name
        } catch {
            return nil
        }
    }

    /// Blocks until queued writes are on disk.
    func flush() {
        queue.sync {}
    }

    /// Size on disk and number of files inside a folder.
    static func directorySize(_ url: URL) -> (bytes: Int64, files: Int) {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return (0, 0) }
        var bytes: Int64 = 0
        var files = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            bytes += Int64(values.totalFileAllocatedSize ?? 0)
            files += 1
        }
        return (bytes, files)
    }
}

/// Chat history: the chats of the ChatGPT account, downloaded and kept on the device, and the
/// replies written in OCTO, which are generated with server-side storage turned off.
@MainActor
@Observable
final class ConversationStore {
    enum SyncState: Equatable {
        case idle
        case syncing
        case failed(String)
    }

    static let pageSize = 50

    private(set) var summaries: [ConversationSummary] = []
    private(set) var projects: [ChatProject] = []
    private(set) var syncState: SyncState = .idle
    private(set) var lastSync: Date?
    /// True while older account chats remain to be listed.
    private(set) var canLoadMore = false
    /// Set when a change couldn't be applied to the ChatGPT account.
    var syncError: String?
    /// Chats of the account matching what's typed in the sidebar's search field, found by ChatGPT.
    private(set) var searchHits: [RemoteSearchHit] = []
    private(set) var isSearchingAccount = false

    @ObservationIgnored private(set) var files: ConversationFiles
    /// Nil in screenshot builds, which never touch the network.
    @ObservationIgnored var service: AccountService?
    @ObservationIgnored private var cache: [UUID: Conversation] = [:]
    @ObservationIgnored private var searchCorpus: [UUID: String] = [:]
    @ObservationIgnored private var corpusLoaded = false
    @ObservationIgnored private(set) var nextOffset = 0
    @ObservationIgnored private var isLoadingMore = false
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var accountSearchTask: Task<Void, Never>?
    @ObservationIgnored private var accountSearchQuery = ""
    /// Bumped on sign-out, so a sync still running doesn't bring the account's chats back.
    @ObservationIgnored private var generation = 0

    init(files: ConversationFiles = ConversationFiles()) {
        self.files = files
        if let index = files.loadIndex() {
            summaries = index
        } else {
            summaries = files.conversationIDs().compactMap { files.loadConversation($0)?.summary }
            if !summaries.isEmpty {
                files.write(nil, index: summaries)
            }
        }
        projects = files.loadProjects()
        sortSummaries()
        Self.protectExistingFiles(in: files.rootDirectory)
    }

    /// Removes from the device the chats last updated before `date`, except pinned ones. Chats
    /// written in OCTO are deleted; chats of the account stay listed and download again when opened.
    @discardableResult
    func removeChats(before date: Date) -> Int {
        let old = summaries.filter { $0.updatedAt < date && !$0.isPinned }
        guard !old.isEmpty else { return 0 }
        removeLocally(old.filter { !$0.isAccountChat }.map(\.id))
        let downloaded = old.filter(\.isAccountChat).map(\.id)
        var attachments: [String] = []
        for id in downloaded {
            let conversation = cache[id] ?? files.loadConversation(id)
            attachments += conversation?.messages.flatMap { $0.attachments.filter(\.isStoredOnDevice).map(\.storedFileName) } ?? []
            cache[id] = nil
            searchCorpus[id] = nil
        }
        files.delete(downloaded, attachmentNames: attachments, index: summaries)
        DevLog.log("storage", "Removed \(old.count) chats last updated before \(date.formatted(.iso8601)) from the device")
        return old.count
    }

    /// Files written before 1.4 stayed readable once the device had been unlocked. They're now
    /// protected like new files: unreadable while the device is locked, unless OCTO has them open.
    private static func protectExistingFiles(in directory: URL) {
        let key = "app.filesProtectedUnlessOpen"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        DispatchQueue.global(qos: .utility).async {
            let fileManager = FileManager.default
            let protection: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.completeUnlessOpen]
            try? fileManager.setAttributes(protection, ofItemAtPath: directory.path)
            let urls = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil)?.allObjects.compactMap { $0 as? URL } ?? []
            for url in urls {
                try? fileManager.setAttributes(protection, ofItemAtPath: url.path)
            }
        }
    }

    /// Chats outside projects, as listed under the sidebar's date sections.
    var looseSummaries: [ConversationSummary] {
        summaries.filter { $0.projectID == nil }
    }

    /// Chats opened in memory, for the developer tools.
    var cachedConversationCount: Int {
        cache.count
    }

    /// The latest chats with their messages, read off the main thread, for the usage estimates.
    /// Chats of the account never opened on this device have no messages to read.
    func recentConversations(limit: Int) async -> [Conversation] {
        let ids = summaries.prefix(limit).map(\.id)
        let opened = ids.compactMap { cache[$0] }
        let unopened = ids.filter { cache[$0] == nil }
        let files = self.files
        let read = await Task.detached(priority: .utility) {
            unopened.compactMap { files.loadConversation($0) }
        }.value
        return opened + read
    }

    func summaries(inProject projectID: String) -> [ConversationSummary] {
        summaries.filter { $0.projectID == projectID }
    }

    func summary(id: UUID) -> ConversationSummary? {
        summaries.first { $0.id == id }
    }

    func conversation(id: UUID) -> Conversation? {
        if let cached = cache[id] { return cached }
        guard var conversation = files.loadConversation(id) else { return nil }
        // Messages interrupted by the app being closed mid-stream.
        for index in conversation.messages.indices where conversation.messages[index].status == .streaming {
            conversation.messages[index].status = .cancelled
        }
        cache[id] = conversation
        return conversation
    }

    func save(_ conversation: Conversation) {
        guard !conversation.messages.isEmpty else { return }
        cache[conversation.id] = conversation
        var summary = conversation.summary
        if let index = summaries.firstIndex(where: { $0.id == conversation.id }) {
            // The chat list may know about a newer account copy than the one saved with the chat.
            summary.remoteUpdatedAt = [summary.remoteUpdatedAt, summaries[index].remoteUpdatedAt].compactMap { $0 }.max()
            summaries[index] = summary
        } else {
            summaries.append(summary)
        }
        sortSummaries()
        if corpusLoaded {
            searchCorpus[conversation.id] = Self.corpus(for: conversation)
        }
        files.write(conversation, index: summaries)
    }

    /// Removes the chat from the device right away, then from the ChatGPT account. Returns once
    /// the account confirmed; when it refuses, the chat comes back with the sync and this throws.
    func delete(id: UUID) async throws {
        let remoteID = remoteID(for: id)
        removeLocally([id])
        DevLog.log("chats", "Deleted \(id) on the device")
        guard let service, let remoteID else { return }
        do {
            try await service.delete(conversationID: remoteID)
            DevLog.log("chats", "Deleted \(remoteID) in the account")
        } catch AccountAPIError.notFound {
            // Already gone from the account.
        } catch {
            DevLog.log("chats", "The account didn't delete \(remoteID): \(DevLog.describe(error))", level: .error)
            await syncWithAccount()
            throw error
        }
    }

    /// Deletes every chat on this device, then in the ChatGPT account.
    func deleteAll() async throws {
        cache.removeAll()
        searchCorpus.removeAll()
        summaries.removeAll()
        projects.removeAll()
        canLoadMore = false
        nextOffset = 0
        files.deleteEverything()
        if let service {
            try await service.deleteAllConversations()
        }
    }

    func setPinned(_ isPinned: Bool, id: UUID) {
        if var conversation = conversation(id: id) {
            conversation.isPinned = isPinned
            save(conversation)
        } else if let index = summaries.firstIndex(where: { $0.id == id }) {
            summaries[index].isPinned = isPinned
            files.write(nil, index: summaries)
        }
    }

    func rename(id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if var conversation = conversation(id: id) {
            conversation.title = trimmed
            save(conversation)
        } else if let index = summaries.firstIndex(where: { $0.id == id }) {
            summaries[index].title = trimmed
            files.write(nil, index: summaries)
        }
        renameInAccount(id: id, title: trimmed)
    }

    /// Applies a new title to the account copy of a chat.
    func renameInAccount(id: UUID, title: String) {
        guard let service, let remoteID = remoteID(for: id), !title.isEmpty else { return }
        Task {
            do {
                try await service.rename(conversationID: remoteID, to: title)
            } catch {
                DevLog.log("chats", "Rename failed for \(remoteID): \(DevLog.describe(error))", level: .error)
                syncError = ChatSession.describe(error)
            }
        }
    }

    func remoteID(for id: UUID) -> String? {
        summaries.first { $0.id == id }?.remoteID ?? cache[id]?.remoteID
    }

    func search(_ query: String) -> [ConversationSummary] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return summaries }
        loadCorpusIfNeeded()
        return summaries.filter { summary in
            summary.title.lowercased().contains(needle) || (searchCorpus[summary.id]?.contains(needle) ?? false)
        }
    }

    /// Also asks the account for chats matching `query`, the way ChatGPT's own search does: it
    /// looks inside the messages and reaches chats this device never downloaded. The chats already
    /// here show while it runs, and a search the account refuses simply adds nothing.
    func searchAccount(_ query: String) {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle != accountSearchQuery else { return }
        accountSearchQuery = needle
        accountSearchTask?.cancel()
        accountSearchTask = nil
        // One letter matches half the history: the account is asked from the second one.
        guard let service, needle.count >= 2 else {
            searchHits = []
            isSearchingAccount = false
            return
        }
        // What the previous letters found stays in place until the new answer arrives, so the
        // list doesn't blink at every keystroke.
        isSearchingAccount = true
        let generation = self.generation
        accountSearchTask = Task { [weak self] in
            // Waits for a pause in the typing, so a word isn't searched letter by letter.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let hits = (try? await service.searchConversations(query: needle)) ?? []
            guard !Task.isCancelled, let self, generation == self.generation, self.accountSearchQuery == needle else { return }
            self.searchHits = hits
            self.isSearchingAccount = false
        }
    }

    /// Puts a chat found in the account into the list, so it opens like any other, and gives back
    /// the id it has on this device.
    func adopt(_ remote: RemoteConversationSummary) -> UUID {
        if let existing = summaries.first(where: { $0.remoteID == remote.id }) {
            return existing.id
        }
        let summary = AccountChatMapper.summary(from: remote, existing: nil)
        summaries.append(summary)
        sortSummaries()
        files.write(nil, index: summaries)
        return summary.id
    }

    // MARK: ChatGPT account

    /// Lists the latest chats and the projects of the account, and forgets chats deleted elsewhere.
    /// The work runs in its own task: pulling to refresh can't cancel it halfway, and a second
    /// call waits for the sync already running instead of returning at once.
    func syncWithAccount() async {
        guard service != nil else { return }
        if let syncTask {
            await syncTask.value
            return
        }
        let task = Task { await performSync() }
        syncTask = task
        await task.value
        if syncTask == task {
            syncTask = nil
        }
    }

    /// Lists the next page of older chats, when the sidebar reaches the end of the list.
    func loadMoreFromAccount() async {
        guard let service, canLoadMore, !isLoadingMore, syncState != .syncing else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = self.generation
        do {
            let page = try await service.conversations(offset: nextOffset, limit: Self.pageSize)
            guard generation == self.generation else { return }
            upsert(page.items)
            nextOffset += page.items.count
            canLoadMore = !page.items.isEmpty && hasMore(after: page)
            files.write(nil, index: summaries)
        } catch let error where error.isCancellation {
            // The end of the list scrolled away: it loads again when it comes back.
        } catch {
            DevLog.log("chats", "Loading older chats failed: \(DevLog.describe(error))", level: .warning)
            canLoadMore = false
        }
    }

    /// Downloads the account copy of a chat and merges it with the replies written in OCTO.
    func downloadAccountChat(id: UUID) async throws -> Conversation? {
        guard let service, let remoteID = remoteID(for: id) else { return nil }
        let remote: RemoteConversation
        do {
            remote = try await service.conversation(id: remoteID)
        } catch AccountAPIError.notFound {
            removeLocally([id])
            throw AccountAPIError.notFound
        }
        var merged = AccountChatMapper.conversation(from: remote, merging: conversation(id: id))
        merged.id = id
        if let summary = summary(id: id) {
            merged.isPinned = summary.isPinned
        }
        save(merged)
        return merged
    }

    /// Frees the space of chats downloaded from the account; they download again when opened.
    /// Chats continued in OCTO keep their file, since those replies only exist on this device.
    func removeDownloadedCopies() -> Int {
        var removed: [UUID] = []
        for summary in summaries where summary.isAccountChat {
            guard let conversation = cache[summary.id] ?? files.loadConversation(summary.id),
                  conversation.messages.allSatisfy({ $0.remoteID != nil })
            else { continue }
            removed.append(summary.id)
            cache[summary.id] = nil
            searchCorpus[summary.id] = nil
        }
        files.deleteConversationFiles(removed)
        DevLog.log("storage", "Removed \(removed.count) downloaded chats")
        return removed.count
    }

    func storageUsage(accountDirectory: URL) async -> StorageUsage {
        let files = files
        return await Task.detached(priority: .utility) {
            files.flush()
            let chats = ConversationFiles.directorySize(files.conversationsDirectory)
            let attachments = ConversationFiles.directorySize(files.attachmentsDirectory)
            let account = ConversationFiles.directorySize(accountDirectory)
            return StorageUsage(
                chatsBytes: chats.bytes,
                chatFiles: chats.files,
                attachmentsBytes: attachments.bytes,
                attachmentFiles: attachments.files,
                accountBytes: account.bytes
            )
        }.value
    }

    /// Reads the chats of another account, when you switch to it. Everything held for the previous
    /// account is dropped first, so nothing of one account shows up under another.
    func use(files: ConversationFiles) {
        generation += 1
        syncTask?.cancel()
        syncTask = nil
        accountSearchTask?.cancel()
        accountSearchTask = nil
        accountSearchQuery = ""
        searchHits = []
        isSearchingAccount = false
        self.files.flush()
        self.files = files
        cache.removeAll()
        searchCorpus.removeAll()
        corpusLoaded = false
        summaries = files.loadIndex() ?? []
        projects = files.loadProjects()
        canLoadMore = false
        nextOffset = 0
        syncState = .idle
        lastSync = nil
        syncError = nil
        sortSummaries()
    }

    /// Forgets the account's chats on sign-out. Chats started in OCTO stay on the device.
    func removeAccountChats() {
        generation += 1
        syncTask?.cancel()
        syncTask = nil
        accountSearchTask?.cancel()
        accountSearchTask = nil
        accountSearchQuery = ""
        searchHits = []
        isSearchingAccount = false
        removeLocally(summaries.filter(\.isAccountChat).map(\.id))
        projects = []
        files.writeProjects([])
        canLoadMore = false
        nextOffset = 0
        syncState = .idle
        lastSync = nil
    }

    #if OCTO_DEMO
    func useDemoProjects(_ demoProjects: [ChatProject]) {
        projects = demoProjects
    }
    #endif

    // MARK: Attachments

    func storeAttachment(_ pending: PendingAttachment) -> MessageAttachment? {
        switch pending.content {
        case .image(let data):
            guard let name = files.saveAttachment(data, fileExtension: "jpg") else { return nil }
            return MessageAttachment(kind: .image, storedFileName: name, displayName: pending.name, mimeType: "image/jpeg", byteCount: data.count)
        case .text(let text):
            let data = Data(text.utf8)
            guard let name = files.saveAttachment(data, fileExtension: "txt") else { return nil }
            return MessageAttachment(kind: .text, storedFileName: name, displayName: pending.name, mimeType: "text/plain", byteCount: data.count)
        }
    }

    /// Keeps an image ChatGPT drew, next to the photos sent in the chats.
    func storeGeneratedImage(_ data: Data) -> MessageAttachment? {
        guard let name = files.saveAttachment(data, fileExtension: "png") else { return nil }
        return MessageAttachment(
            kind: .image,
            storedFileName: name,
            displayName: String(localized: "Image created by ChatGPT"),
            mimeType: "image/png",
            byteCount: data.count
        )
    }

    /// Reads an attachment off the main actor, while a reply is being prepared. The folder is
    /// handed in, captured on the main actor by the caller, so switching account mid-reply can
    /// never point this at another account's files.
    nonisolated func payload(for attachment: MessageAttachment, files: ConversationFiles) -> AttachmentPayload? {
        guard let url = files.attachmentURL(attachment.storedFileName), let data = try? Data(contentsOf: url) else { return nil }
        switch attachment.kind {
        case .image:
            return .imageDataURL("data:\(attachment.mimeType);base64,\(data.base64EncodedString())")
        case .text:
            return .text(String(decoding: data, as: UTF8.self))
        }
    }

    func markdownExport(of conversation: Conversation) -> String {
        var lines = ["# \(conversation.displayTitle)", ""]
        for message in conversation.messages where !message.text.isEmpty {
            let author = message.role == .user ? String(localized: "You") : "ChatGPT"
            lines.append("**\(author)**")
            lines.append("")
            lines.append(message.text)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Private

    private func performSync() async {
        guard let service else { return }
        let generation = self.generation
        syncState = .syncing
        let started = Date()
        DevLog.log("sync", "Listing the account chats")
        do {
            let page = try await service.conversations(offset: 0, limit: Self.pageSize)
            guard generation == self.generation else { return }
            upsert(page.items)
            removeMissingChats(firstPage: page.items, isComplete: page.items.count < Self.pageSize)
            nextOffset = page.items.count
            canLoadMore = hasMore(after: page)
            files.write(nil, index: summaries)
            syncState = .idle
            lastSync = Date()
            DevLog.log("sync", "Listed \(page.items.count) chats (total \(page.total.map(String.init) ?? "?")) in \(Int(Date().timeIntervalSince(started) * 1_000)) ms")
        } catch {
            DevLog.log("sync", "Listing failed: \(DevLog.describe(error))", level: error.isCancellation ? .debug : .error)
            syncState = error.isCancellation ? .idle : .failed(ChatSession.describe(error))
            return
        }
        await syncProjects(service: service)
    }

    private func upsert(_ items: [RemoteConversationSummary]) {
        var indexByRemoteID: [String: Int] = [:]
        for (index, summary) in summaries.enumerated() {
            if let remoteID = summary.remoteID {
                indexByRemoteID[remoteID] = index
            }
        }
        for item in items where !item.isArchived {
            if let index = indexByRemoteID[item.id] {
                summaries[index] = AccountChatMapper.summary(from: item, existing: summaries[index])
            } else {
                summaries.append(AccountChatMapper.summary(from: item, existing: nil))
                indexByRemoteID[item.id] = summaries.count - 1
            }
        }
        sortSummaries()
    }

    /// Chats missing from the first page of the account list were deleted or archived elsewhere,
    /// unless they're older than everything on that page.
    private func removeMissingChats(firstPage items: [RemoteConversationSummary], isComplete: Bool) {
        let listed = Set(items.map(\.id))
        let oldest = items.compactMap(\.updatedAt).min()
        let missing = summaries.filter { summary in
            guard let remoteID = summary.remoteID, summary.projectID == nil, !listed.contains(remoteID) else { return false }
            if isComplete { return true }
            guard let oldest, let updatedAt = summary.remoteUpdatedAt else { return false }
            return updatedAt >= oldest
        }
        if !missing.isEmpty {
            DevLog.log("sync", "Forgetting \(missing.count) chats deleted elsewhere")
            removeLocally(missing.map(\.id))
        }
    }

    private func syncProjects(service: AccountService) async {
        let generation = self.generation
        let remoteProjects: [RemoteProject]
        do {
            remoteProjects = try await service.projects()
        } catch {
            DevLog.log("sync", "Projects failed: \(DevLog.describe(error))", level: .warning)
            return
        }
        guard generation == self.generation else { return }
        projects = remoteProjects.map { ChatProject(id: $0.id, name: $0.name, iconName: $0.iconName, colorHex: $0.colorHex) }

        var items: [RemoteConversationSummary] = []
        var completeProjects = Set<String>()
        for project in remoteProjects {
            var chats = project.conversations
            var cursor = project.conversationsCursor
            for _ in 0..<10 {
                guard let next = cursor else { break }
                guard let page = try? await service.projectConversations(projectID: project.id, cursor: next) else { break }
                chats += page.items
                cursor = page.items.isEmpty || page.cursor == next ? nil : page.cursor
            }
            if cursor == nil {
                completeProjects.insert(project.id)
            }
            items += chats.map { chat in
                var chat = chat
                chat.projectID = project.id
                return chat
            }
        }
        guard generation == self.generation else { return }
        upsert(items)

        let listed = Set(items.map(\.id))
        let projectIDs = Set(projects.map(\.id))
        // The sidebar endpoint returns up to 20 projects: chats of unlisted projects are kept if there may be more.
        let allProjectsListed = remoteProjects.count < 20
        let missing = summaries.filter { summary in
            guard let remoteID = summary.remoteID, let projectID = summary.projectID else { return false }
            if !projectIDs.contains(projectID) { return allProjectsListed }
            return completeProjects.contains(projectID) && !listed.contains(remoteID)
        }
        if !missing.isEmpty {
            removeLocally(missing.map(\.id))
        }
        files.writeProjects(projects)
        files.write(nil, index: summaries)
        DevLog.log("sync", "Listed \(projects.count) projects with \(items.count) chats")
    }

    private func hasMore(after page: RemoteConversationPage) -> Bool {
        if let total = page.total {
            return nextOffset < total
        }
        return page.items.count >= Self.pageSize
    }

    private func removeLocally(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let removed = Set(ids)
        var names: [String] = []
        for id in ids {
            let conversation = cache[id] ?? files.loadConversation(id)
            names += conversation?.messages.flatMap { $0.attachments.filter(\.isStoredOnDevice).map(\.storedFileName) } ?? []
            cache[id] = nil
            searchCorpus[id] = nil
        }
        summaries.removeAll { removed.contains($0.id) }
        files.delete(ids, attachmentNames: names, index: summaries)
    }

    private func loadCorpusIfNeeded() {
        guard !corpusLoaded else { return }
        corpusLoaded = true
        for summary in summaries {
            if let conversation = cache[summary.id] ?? files.loadConversation(summary.id) {
                searchCorpus[summary.id] = Self.corpus(for: conversation)
            }
        }
    }

    private static func corpus(for conversation: Conversation) -> String {
        String(conversation.messages.map(\.text).joined(separator: "\n").prefix(50_000)).lowercased()
    }

    private func sortSummaries() {
        summaries.sort { $0.updatedAt > $1.updatedAt }
    }
}
