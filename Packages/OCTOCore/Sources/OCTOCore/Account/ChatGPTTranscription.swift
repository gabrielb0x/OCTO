import Foundation

/// ChatGPT's dictation (`POST /backend-api/transcribe`): a recording goes up as a multipart
/// upload and its text comes back, with the same session as the rest of the account.
public enum ChatGPTTranscription {
    public static var url: URL { ChatGPTAccountAPI.url("transcribe") }

    /// ChatGPT turns down recordings shorter than this.
    public static let minimumDuration: TimeInterval = 0.1
    /// ChatGPT's dictation stops recording after 10 minutes.
    public static let maximumDuration: TimeInterval = 600

    /// The upload ChatGPT's own dictation sends from Safari: the recording as `file`, named
    /// "whisper.mp4", then its length in milliseconds. The server detects the language.
    public static func form(audio: Data, durationMilliseconds: Int?, fileName: String = "whisper.mp4", mimeType: String = "audio/mp4") -> MultipartForm {
        var form = MultipartForm()
        form.addFile("file", fileName: fileName, mimeType: mimeType, data: audio)
        if let durationMilliseconds {
            form.addField("duration_ms", value: String(durationMilliseconds))
        }
        return form
    }

    /// The text of a transcription, `{"text": "…"}`. Empty when nothing was heard.
    public static func parse(_ data: Data) -> String? {
        guard let object = JSONValue.object(data) else { return nil }
        for key in ["text", "transcript", "transcription"] {
            if let text = JSONValue.string(object[key]) {
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
}

/// A `multipart/form-data` body.
public struct MultipartForm: Sendable {
    public let boundary: String
    private var body = Data()

    public init(boundary: String = "OCTO-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    public mutating func addField(_ name: String, value: String) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(Self.quoted(name))\"\r\n\r\n\(value)\r\n")
    }

    public mutating func addFile(_ name: String, fileName: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(Self.quoted(name))\"; filename=\"\(Self.quoted(fileName))\"\r\nContent-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    public func encoded() -> Data {
        body + Data("--\(boundary)--\r\n".utf8)
    }

    private mutating func append(_ text: String) {
        body.append(Data(text.utf8))
    }

    static func quoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }
}
