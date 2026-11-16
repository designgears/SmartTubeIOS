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

    @Test func hiddenProfilesAreLeftOffWhosWatching() {
        var saved = account(gaia: "1", primary: "Me")
        saved.channels = [
            YouTubeChannel(name: "Me", avatarURL: nil, pageId: nil),
            YouTubeChannel(name: "Me", avatarURL: nil, pageId: "brand"),
        ]
        let profiles = AccountProfile.profiles(for: saved)
        let brand = AccountProfile.slot(accountId: saved.id, pageId: "brand")

        let shown = AccountProfile.shown(profiles, hidden: [brand], activeId: saved.id)
        #expect(shown.map(\.id) == [saved.id])
    }

    @Test func theProfileInUseIsShownEvenWhenHidden() {
        let saved = account(gaia: "1", primary: "Me")
        let profiles = AccountProfile.profiles(for: saved)

        let shown = AccountProfile.shown(profiles, hidden: [saved.id], activeId: saved.id)
        #expect(shown.map(\.id) == [saved.id])
        #expect(AccountProfile.shown(profiles, hidden: [saved.id], activeId: nil).isEmpty)
    }

    @Test func slotMapsBackToItsAccount() {
        #expect(AccountProfile.accountId(ofSlot: "A") == "A")
        #expect(AccountProfile.accountId(ofSlot: AccountProfile.slot(accountId: "A", pageId: "p1")) == "A")
    }

    @Test func eachChannelIsItsOwnProfile() {
        var saved = account(gaia: "1", primary: "Aunt")
        saved.channels = [
            YouTubeChannel(name: "Aunt", avatarURL: nil, pageId: nil),
            YouTubeChannel(name: "Aunt's Garden", avatarURL: nil, pageId: "p1"),
            YouTubeChannel(name: "Aunt's Recipes", avatarURL: nil, pageId: "p2"),
        ]
        let profiles = AccountProfile.profiles(for: saved)
        #expect(profiles.map(\.name) == ["Aunt", "Aunt's Garden", "Aunt's Recipes"])
        // Primary keeps the bare account id as its data slot; Brand channels get their own.
        #expect(profiles.map(\.id) == [saved.id, "\(saved.id).channel.p1", "\(saved.id).channel.p2"])
    }

    @Test func accountWithoutKnownChannelsIsOneProfile() {
        let saved = account(gaia: "1", primary: "Me")
        let profiles = AccountProfile.profiles(for: saved)
        #expect(profiles.count == 1)
        #expect(profiles.first?.id == saved.id)
        #expect(profiles.first?.name == "Me")
    }

    @Test func roundTripsThroughJSON() throws {
        var saved = account(gaia: "42", primary: "Bob")
        saved.refreshToken = "r"
        saved.pageId = "brand"
        let decoded = try JSONDecoder().decode([SavedAccount].self, from: JSONEncoder().encode([saved]))
        #expect(decoded == [saved])
    }
}
