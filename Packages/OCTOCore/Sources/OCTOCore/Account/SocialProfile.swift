import Foundation

/// The profile people see of you in ChatGPT — display name, username and photo — as its group
/// chats show it (`GET /calpico/chatgpt/profile/{user_id}`, "calpico" being ChatGPT's own name
/// for group chats). Its photo is the account's profile picture.
public struct SocialProfile: Codable, Equatable, Sendable {
    public var userID: String
    public var username: String?
    public var displayName: String?
    public var pictureURL: URL?

    public init(userID: String, username: String? = nil, displayName: String? = nil, pictureURL: URL? = nil) {
        self.userID = userID
        self.username = username
        self.displayName = displayName
        self.pictureURL = pictureURL
    }

    public static func parse(_ data: Data) -> SocialProfile? {
        guard let object = JSONValue.object(data),
              let userID = JSONValue.string(object["user_id"]), !userID.isEmpty
        else { return nil }
        func text(_ key: String) -> String? {
            let value = JSONValue.string(object[key])?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        return SocialProfile(
            userID: userID,
            username: text("username"),
            displayName: text("display_name"),
            pictureURL: text("profile_picture_url").flatMap(URL.init(string:))
        )
    }
}

/// The calls of ChatGPT's own "Edit profile", read from its web app: the username has an address
/// of its own, the display name and the photo go to the profile. A photo is uploaded first, then
/// the profile is pointed at it.
public enum SocialProfileAPI {
    /// `GET` reads the profile; `POST` with `{"display_name": …}` or `{"profile_asset_pointer": …}`
    /// changes it, and answers with the profile as it now is.
    public static func profileURL(userID: String) -> URL {
        ChatGPTAccountAPI.url("calpico/chatgpt/profile/\(ChatGPTAccountAPI.pathSegment(userID))")
    }

    /// `POST` with `{"username": …}`, answered with the profile.
    public static func usernameURL(userID: String) -> URL {
        ChatGPTAccountAPI.url("calpico/chatgpt/profile/\(ChatGPTAccountAPI.pathSegment(userID))/username")
    }

    /// `POST` of the photo as a `file` form field, answered with `{"asset_pointer": …}`.
    public static var photoUploadURL: URL { ChatGPTAccountAPI.url("calpico/chatgpt/profile_files") }

    /// Where the website sends the photo instead once a flag of its own is on: the upload goes to
    /// `…/photo`, then `PATCH` of the profile with `{"profile_asset_pointer": …}`. Tried when the
    /// addresses above no longer exist.
    public static var codexProfileURL: URL { ChatGPTAccountAPI.url("wham/profiles/me") }
    public static var codexPhotoUploadURL: URL { ChatGPTAccountAPI.url("wham/profiles/me/photo") }

    /// ChatGPT refuses photos above this size.
    public static let maximumPhotoBytes = 5 * 1024 * 1024

    public static func displayNameBody(_ name: String) -> Data {
        body(["display_name": name])
    }

    public static func usernameBody(_ username: String) -> Data {
        body(["username": username])
    }

    public static func photoBody(assetPointer: String) -> Data {
        body(["profile_asset_pointer": assetPointer])
    }

    /// The upload of a photo, like the file picker of the website sends it.
    public static func photoForm(jpeg: Data, fileName: String = "profile.jpg") -> MultipartForm {
        var form = MultipartForm()
        form.addFile("file", fileName: fileName, mimeType: "image/jpeg", data: jpeg)
        return form
    }

    /// The `asset_pointer` of an uploaded photo, such as `sediment://file_…`.
    public static func assetPointer(in data: Data) -> String? {
        guard let pointer = JSONValue.string(JSONValue.object(data)?["asset_pointer"]), !pointer.isEmpty else { return nil }
        return pointer
    }

    /// The profile in the answer of `PATCH wham/profiles/me`, which nests it under `profile`.
    public static func profile(inCodexResponse data: Data, userID: String) -> SocialProfile? {
        guard let object = JSONValue.object(data), let profile = object["profile"] as? [String: Any] else { return nil }
        var merged = profile
        if merged["user_id"] == nil {
            merged["user_id"] = userID
        }
        guard let nested = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return SocialProfile.parse(nested)
    }

    /// A username as typed, without spaces around it or the "@" people tend to put first.
    public static func normalizedUsername(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("@") {
            value.removeFirst()
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizedDisplayName(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func body(_ object: [String: String]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}
