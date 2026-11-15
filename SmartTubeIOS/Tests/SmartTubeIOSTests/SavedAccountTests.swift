import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("Saved accounts")
struct SavedAccountTests {
    private func account(gaia: String? = nil, primary: String? = nil) -> SavedAccount {
        var saved = SavedAccount()
        saved.gaiaId = gaia
        saved.primaryName = primary
        return saved
    }

    @Test func gaiaIdDecidesWhenBothKnown() {
        #expect(account(gaia: "1", primary: "Bob").isSameGoogleAccount(as: account(gaia: "1", primary: "Robert")))
        #expect(!account(gaia: "1", primary: "Bob").isSameGoogleAccount(as: account(gaia: "2", primary: "Bob")))
    }

    /// Regression: matching names must never merge accounts (a wrong match deleted one).
    @Test func namesAloneNeverMatch() {
        #expect(!account(primary: "Bobby Corder").isSameGoogleAccount(as: account(primary: "bobby corder")))
        #expect(!account(primary: "Bobby").isSameGoogleAccount(as: account(primary: "Alice")))
    }

    /// Regression: a second account must never replace the first just because their
    /// display names match while one of them has no Google id yet.
    @Test func nameDoesNotMatchWhenOnlyOneSideHasAnId() {
        #expect(!account(gaia: "1", primary: "Bob").isSameGoogleAccount(as: account(primary: "Bob")))
        #expect(!account(primary: "Bob").isSameGoogleAccount(as: account(gaia: "2", primary: "Bob")))
    }

    @Test func unknownIdentityNeverMatches() {
        #expect(!account().isSameGoogleAccount(as: account()))
        #expect(!account(primary: "").isSameGoogleAccount(as: account(primary: "")))
    }

    @Test func roundTripsThroughJSON() throws {
        var saved = account(gaia: "42", primary: "Bob")
        saved.refreshToken = "r"
        saved.pageId = "brand"
        let decoded = try JSONDecoder().decode([SavedAccount].self, from: JSONEncoder().encode([saved]))
        #expect(decoded == [saved])
    }
}
