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

@Suite struct ContactMaskingTests {
    @Test func hidesAnEmailAddressButKeepsItRecognizable() {
        #expect(ContactMasking.email("gabriel@example.com") == "g••••••@e••••••.com")
        #expect(ContactMasking.email("a@b.fr") == "•@•.fr")
        #expect(ContactMasking.email("gabriel.badre.long.address@protonmail.com") == "g••••••••@p••••••••.com")
        // A domain without an extension, and values that aren't addresses, are hidden all the same.
        #expect(ContactMasking.email("me@localhost") == "m•@l••••••••")
        #expect(ContactMasking.email("not an address") == "n••••••••")
        #expect(ContactMasking.email("") == "")
    }

    @Test func keepsTheShapeOfAPhoneNumberAndItsLastDigits() {
        #expect(ContactMasking.phone("+33 6 12 34 56 78") == "+•• • •• •• •• 78")
        #expect(ContactMasking.phone("0612345678") == "••••••••78")
        // Too short to hide anything useful: every digit goes.
        #expect(ContactMasking.phone("1234") == "••••")
        #expect(ContactMasking.phone("") == "")
    }

    @Test func hidesAnyOtherValue() {
        #expect(ContactMasking.text("Gabriel") == "G••••••")
        #expect(ContactMasking.text("G") == "•")
        #expect(ContactMasking.text("  ") == "")
    }
}
