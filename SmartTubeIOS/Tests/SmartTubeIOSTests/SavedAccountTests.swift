import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("Saved accounts")
struct SavedAccountTests {
    private func account(gaia: String? = nil, primary: String? = nil) -> SavedAccount {
        var a = SavedAccount()
        a.gaiaId = gaia
        a.primaryName = primary
        return a
    }

    @Test func gaiaIdDecidesWhenBothKnown() {
        #expect(account(gaia: "1", primary: "Bob").isSameGoogleAccount(as: account(gaia: "1", primary: "Robert")))
        #expect(!account(gaia: "1", primary: "Bob").isSameGoogleAccount(as: account(gaia: "2", primary: "Bob")))
    }

    @Test func primaryNameIsTheFallback() {
        #expect(account(primary: "Bobby Corder").isSameGoogleAccount(as: account(primary: "bobby corder")))
        #expect(!account(primary: "Bobby").isSameGoogleAccount(as: account(primary: "Alice")))
    }

    @Test func unknownIdentityNeverMatches() {
        #expect(!account().isSameGoogleAccount(as: account()))
        #expect(!account(primary: "").isSameGoogleAccount(as: account(primary: "")))
    }

    @Test func roundTripsThroughJSON() throws {
        var a = account(gaia: "42", primary: "Bob")
        a.refreshToken = "r"
        a.pageId = "brand"
        let decoded = try JSONDecoder().decode([SavedAccount].self, from: JSONEncoder().encode([a]))
        #expect(decoded == [a])
    }
}
