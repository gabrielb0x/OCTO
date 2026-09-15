import Observation
import OCTOCore
import UIKit
import UserNotifications

/// Tells you when ChatGPT has finished replying while OCTO is in the background, and keeps
/// replies generating for the time iOS allows once the app leaves the screen.
@MainActor
@Observable
final class ReplyNotifications {
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// Chat to open after a notification was tapped.
    var conversationToOpen: UUID?

    @ObservationIgnored private let delegate = NotificationDelegate()
    @ObservationIgnored private var backgroundTasks: [UUID: UIBackgroundTaskIdentifier] = [:]
    @ObservationIgnored private let isDemo: Bool

    init(isDemo: Bool) {
        self.isDemo = isDemo
        guard !isDemo else { return }
        UNUserNotificationCenter.current().delegate = delegate
        delegate.onOpen = { [weak self] id in
            self?.conversationToOpen = id
        }
    }

    var isAuthorized: Bool {
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
    }

    func refreshAuthorization() async {
        guard !isDemo else { return }
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        guard !isDemo else { return false }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        DevLog.log("notifications", "Authorization \(granted ? "granted" : "denied")")
        return granted
    }

    /// Asks iOS for time to finish the reply if the app goes to the background.
    func replyStarted(_ conversationID: UUID) {
        guard !isDemo, backgroundTasks[conversationID] == nil else { return }
        let identifier = UIApplication.shared.beginBackgroundTask(withName: "OCTO reply") { [weak self] in
            MainActor.assumeIsolated {
                self?.endBackgroundTask(for: conversationID)
            }
        }
        if identifier != .invalid {
            backgroundTasks[conversationID] = identifier
        }
    }

    /// Posts a notification when the reply finished while OCTO wasn't on screen.
    func replyFinished(_ conversationID: UUID, title: String, reply: String, failed: Bool, settings: AppSettings) {
        guard !isDemo else { return }
        guard settings.notifiesReplies, isAuthorized, UIApplication.shared.applicationState != .active else {
            endBackgroundTask(for: conversationID)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title.isEmpty ? "ChatGPT" : title
        if failed {
            content.body = String(localized: "ChatGPT couldn't finish replying.")
        } else if settings.showsNotificationPreviews {
            let preview = MarkdownPlainText.strip(reply).trimmingCharacters(in: .whitespacesAndNewlines)
            content.body = preview.isEmpty ? String(localized: "ChatGPT replied.") : String(preview.prefix(180))
        } else {
            content.body = String(localized: "ChatGPT replied.")
        }
        content.sound = .default
        content.threadIdentifier = conversationID.uuidString
        content.userInfo = ["conversationID": conversationID.uuidString]
        let request = UNNotificationRequest(identifier: "reply-\(conversationID.uuidString)", content: content, trigger: nil)
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                DevLog.log("notifications", "Posted reply notification for \(conversationID)")
            } catch {
                DevLog.log("notifications", "Couldn't post: \(DevLog.describe(error))", level: .error)
            }
            endBackgroundTask(for: conversationID)
        }
    }

    /// A notification a few seconds from now, to try them out from the developer tools.
    func sendTest(after seconds: TimeInterval = 5) async {
        if authorization == .notDetermined {
            _ = await requestAuthorization()
        }
        let content = UNMutableNotificationContent()
        content.title = "OCTO"
        content.body = String(localized: "Notifications work.")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "octo-test", content: content, trigger: trigger))
    }

    private func endBackgroundTask(for conversationID: UUID) {
        guard let identifier = backgroundTasks.removeValue(forKey: conversationID) else { return }
        UIApplication.shared.endBackgroundTask(identifier)
    }
}

private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: (@MainActor @Sendable (UUID) -> Void)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let value = response.notification.request.content.userInfo["conversationID"] as? String,
              let id = UUID(uuidString: value)
        else { return }
        let handler = onOpen
        await MainActor.run {
            handler?(id)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
