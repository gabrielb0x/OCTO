import Foundation
import Testing
@testable import OCTOCore

@Suite struct LinkCleanerTests {
    @Test func removesTrackingParameters() throws {
        let article = try #require(URL(string: "https://www.example.com/article?id=42&utm_source=chatgpt.com&UTM_Medium=x&fbclid=abc#part"))
        #expect(LinkCleaner.clean(article).absoluteString == "https://www.example.com/article?id=42#part")
        #expect(LinkCleaner.clean(try #require(URL(string: "https://example.com/?utm_source=chatgpt.com"))).absoluteString == "https://example.com/")
        #expect(LinkCleaner.clean(try #require(URL(string: "https://youtu.be/abc?si=XYZ&t=42"))).absoluteString == "https://youtu.be/abc?t=42")
        #expect(LinkCleaner.clean(try #require(URL(string: "https://example.com/search?q=si&si=keep"))).absoluteString == "https://example.com/search?q=si&si=keep")

        let mail = try #require(URL(string: "mailto:me@example.com?subject=utm_source"))
        #expect(LinkCleaner.clean(mail) == mail)
        let plain = try #require(URL(string: "https://example.com/page"))
        #expect(LinkCleaner.clean(plain) == plain)
    }

    @Test func keepsUploadsOutOfTheNetworkLog() {
        let upload = Data("--B\r\nContent-Disposition: form-data; name=\"file\"\r\n\r\nvoice".utf8)
        #expect(HTTPLogRedactor.body(upload, contentType: "multipart/form-data; boundary=B") == "<\(upload.count) bytes of form data>")
    }

    @Test func cleansTheLinksOfAText() {
        let text = "Voir [ce site](https://example.com/a?utm_source=chatgpt.com) et https://example.com/b?ref=1&gclid=2."
        #expect(LinkCleaner.cleanLinks(in: text) == "Voir [ce site](https://example.com/a) et https://example.com/b?ref=1.")
        #expect(LinkCleaner.cleanLinks(in: "Pas de lien ici ?") == "Pas de lien ici ?")
    }
}
