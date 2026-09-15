import Foundation
import Testing
@testable import OCTOCore

@Suite struct TranscriptionTests {
    @Test func uploadsTheRecordingAsMultipart() {
        var form = MultipartForm(boundary: "B")
        form.addField("language", value: "fr")
        form.addFile("file", fileName: "audio.m4a", mimeType: "audio/mp4", data: Data([0x01, 0x02]))
        var expected = Data("--B\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\nfr\r\n".utf8)
        expected += Data("--B\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8)
        expected += Data([0x01, 0x02])
        expected += Data("\r\n--B--\r\n".utf8)
        #expect(form.encoded() == expected)
        #expect(form.contentType == "multipart/form-data; boundary=B")
        #expect(MultipartForm.quoted("a\"b\r\n") == "a%22b")
    }

    @Test func sendsTheRecordingLikeChatGPT() {
        let upload = String(decoding: ChatGPTTranscription.form(audio: Data([0x0A]), durationMilliseconds: 1_250).encoded(), as: UTF8.self)
        #expect(upload.contains("name=\"file\"; filename=\"whisper.mp4\"\r\nContent-Type: audio/mp4\r\n\r\n\n\r\n"))
        #expect(upload.contains("name=\"duration_ms\"\r\n\r\n1250\r\n"))
        #expect(upload.range(of: "name=\"file\"")!.lowerBound < upload.range(of: "name=\"duration_ms\"")!.lowerBound)
        #expect(!String(decoding: ChatGPTTranscription.form(audio: Data(), durationMilliseconds: nil).encoded(), as: UTF8.self).contains("duration_ms"))
    }

    @Test func readsTheTranscribedText() {
        #expect(ChatGPTTranscription.url.absoluteString == "https://chatgpt.com/backend-api/transcribe")
        #expect(ChatGPTTranscription.parse(Data(#"{"text":" Bonjour à tous "}"#.utf8)) == "Bonjour à tous")
        #expect(ChatGPTTranscription.parse(Data(#"{"text":""}"#.utf8)) == "")
        #expect(ChatGPTTranscription.parse(Data(#"{"detail":"Unauthorized"}"#.utf8)) == nil)
        #expect(ChatGPTTranscription.parse(Data("not json".utf8)) == nil)
    }
}
