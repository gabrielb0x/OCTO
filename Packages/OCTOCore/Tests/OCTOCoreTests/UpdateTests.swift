import Foundation
import Testing
@testable import OCTOCore

@Suite struct UpdateTests {
    @Test func comparesVersions() throws {
        #expect(try #require(SemanticVersion("v1.10.0")) > (try #require(SemanticVersion("1.9.3"))))
        #expect(SemanticVersion("1.3") == SemanticVersion("1.3.0"))
        #expect(SemanticVersion("2.0.0-beta.1") == SemanticVersion("2.0.0"))
        #expect(SemanticVersion("1.3.0")?.description == "1.3.0")
        #expect(SemanticVersion("latest") == nil)
        #expect(SemanticVersion("1..2") == nil)
    }

    @Test func readsTheLatestRelease() throws {
        let json = #"{"tag_name":"v1.4.0","name":"OCTO v1.4.0","html_url":"https://github.com/gabrielb0x/OCTO/releases/tag/v1.4.0","draft":false,"prerelease":false,"published_at":"2026-09-16T10:00:00Z","body":"**Ajouté**\n\n- Truc\n","assets":[{"name":"OCTO-1.4.0.ipa","browser_download_url":"https://github.com/gabrielb0x/OCTO/releases/download/v1.4.0/OCTO-1.4.0.ipa","size":3328389}]}"#
        let release = try #require(AppRelease.parse(Data(json.utf8)))
        #expect(release.version == "1.4.0")
        #expect(release.title == "OCTO v1.4.0")
        #expect(release.notes == "**Ajouté**\n\n- Truc")
        #expect(release.ipaURL?.lastPathComponent == "OCTO-1.4.0.ipa")
        #expect(release.ipaSize == 3_328_389)
        #expect(release.publishedAt != nil)
        #expect(release.isNewer(than: "1.3.0"))
        #expect(!release.isNewer(than: "1.4.0"))
        #expect(!release.isNewer(than: "1.10.0"))
        #expect(release.installURL(scheme: "altstore")?.absoluteString == "altstore://install?url=https://github.com/gabrielb0x/OCTO/releases/download/v1.4.0/OCTO-1.4.0.ipa")
        #expect(AppRelease.latestURL(repository: "gabrielb0x/OCTO").absoluteString == "https://api.github.com/repos/gabrielb0x/OCTO/releases/latest")

        #expect(AppRelease.parse(Data(#"{"tag_name":"v2.0.0","html_url":"https://github.com","draft":true}"#.utf8)) == nil)
        #expect(AppRelease.parse(Data(#"{"message":"Not Found"}"#.utf8)) == nil)
    }

    @Test func checksAFewTimesADay() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(UpdateSchedule.isDue(lastCheck: nil, now: start))
        #expect(!UpdateSchedule.isDue(lastCheck: start, now: start.addingTimeInterval(3_600)))
        #expect(UpdateSchedule.isDue(lastCheck: start, now: start.addingTimeInterval(7 * 3_600)))
        #expect(UpdateSchedule.isDue(lastCheck: start, now: start.addingTimeInterval(-60)))
    }
}
