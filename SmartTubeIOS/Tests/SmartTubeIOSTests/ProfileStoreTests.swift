import Foundation
import Testing

@testable import SmartTubeIOSCore

@Suite("ProfileStore — people on Who's Watching?")
@MainActor
struct ProfileStoreTests {
    private func makeDefaults() -> UserDefaults {
        // swiftlint:disable:next force_unwrapping
        UserDefaults(suiteName: "profiles-\(UUID().uuidString)")!  // a fresh suite name always works
    }

    private func channel(_ account: String, _ page: String? = nil, _ name: String) -> AccountProfile {
        AccountProfile(accountId: account, pageId: page, name: name, avatarURL: nil)
    }

    private let alex = YouTubeAccountKey(accountId: "A", pageId: nil)
    private let alexKids = YouTubeAccountKey(accountId: "A", pageId: "kids")
    private let sam = YouTubeAccountKey(accountId: "S", pageId: nil)

    private var channels: [AccountProfile] {
        [channel("A", nil, "Alex"), channel("A", "kids", "Alex Kids"), channel("S", nil, "Sam")]
    }

    /// Every Who's Watching? entry from before profiles becomes a profile under its own slot,
    /// so its data stays where it is; the live channel's profile is the one in use.
    @Test func migrationKeepsEveryChannelsSlot() {
        let store = ProfileStore(defaults: makeDefaults())
        store.sync(channels: channels, live: alexKids)
        #expect(store.profiles.map(\.id) == ["A", "A.channel.kids", "S"])
        #expect(store.profiles.map(\.name) == ["Alex", "Alex Kids", "Sam"])
        #expect(store.activeId == "A.channel.kids")
        #expect(store.active?.mainYouTube == alexKids)
    }

    @Test func signedOutFirstRunIsGuest() {
        let store = ProfileStore(defaults: makeDefaults())
        store.sync(channels: channels, live: nil)
        #expect(store.activeId == nil && store.profiles.count == 3)
    }

    @Test func persists() {
        let defaults = makeDefaults()
        let store = ProfileStore(defaults: defaults)
        store.sync(channels: channels, live: sam)
        let reloaded = ProfileStore(defaults: defaults)
        #expect(reloaded.profiles == store.profiles && reloaded.activeId == "S")
    }

    /// Switching the live channel outside a profile switch (another channel picked, an account
    /// signed in) puts its profile in use.
    @Test func theLiveChannelsProfileIsInUse() {
        let store = ProfileStore(defaults: makeDefaults())
        store.sync(channels: channels, live: alex)
        store.sync(channels: channels, live: sam)
        #expect(store.activeId == "S")
        // No live session (Guest, a profile without YouTube): the profile in use stays.
        store.sync(channels: channels, live: nil)
        #expect(store.activeId == "S")
    }

    /// A channel is turned into a profile once: names follow the channel until renamed, and a
    /// profile that already uses it isn't duplicated.
    @Test func channelsBecomeProfilesOnce() {
        let store = ProfileStore(defaults: makeDefaults())
        store.sync(channels: [channel("A", nil, "Alex")], live: alex)
        store.sync(channels: [channel("A", nil, "Alex B."), channel("A", "kids", "Alex Kids")], live: alex)
        #expect(store.profiles.map(\.name) == ["Alex B.", "Alex Kids"])
        store.sync(channels: channels, live: alex)
        #expect(store.profiles.count == 3)
    }

    /// Add YouTube Account on a profile: the new account joins it (and becomes its main one
    /// when it had none) instead of getting profiles of its own.
    @Test func anAddedAccountJoinsTheTargetProfile() {
        let store = ProfileStore(defaults: makeDefaults())
        store.sync(channels: [channel("A", nil, "Alex")], live: alex)
        store.addAccountTarget = "A"
        let withSam = [channel("A", nil, "Alex"), channel("S", nil, "Sam"), channel("S", "b", "Sam Brand")]
        store.sync(channels: withSam, live: sam)
        #expect(store.profiles.map(\.id) == ["A"])
        #expect(store.active?.youtube == [alex, sam])
        #expect(store.active?.mainYouTube == sam)  // the live one is the main one
        #expect(store.addAccountTarget == nil)
    }

    @Test func signingOutRemovesOnlyProfilesMadeForTheAccount() {
        let store = ProfileStore(defaults: makeDefaults())
        store.sync(channels: channels, live: alex)
        store.addAccountTarget = "A"
        let withJo = channels + [channel("J", nil, "Jo")]
        store.sync(channels: withJo, live: YouTubeAccountKey(accountId: "J", pageId: nil))

        // Alex's profile has Jo too: it stays, on Jo; Alex Kids (Alex's own) goes with its data.
        let removed = store.removeYouTubeAccount("A")
        #expect(removed == ["A.channel.kids"])
        #expect(store.profile(id: "A")?.youtube == [YouTubeAccountKey(accountId: "J", pageId: nil)])
        #expect(store.profile(id: "A")?.mainYouTube?.accountId == "J")
        #expect(store.activeId == "A")

        #expect(store.removeYouTubeAccount("S") == ["S"])
        #expect(store.removeYouTubeAccount("J") == ["A"])
        #expect(store.activeId == nil && store.profiles.isEmpty)
    }

    /// The same Google account signed in again keeps its original entry: the short-lived
    /// entry's profile goes, and a profile it joined takes the original instead.
    @Test func reSigningInHandsOverToTheOriginalEntry() {
        let store = ProfileStore(defaults: makeDefaults())
        store.sync(channels: [channel("A", nil, "Alex")], live: alex)
        store.sync(
            channels: [channel("A", nil, "Alex"), channel("T", nil, "Alex")], live: .init(accountId: "T", pageId: nil))
        #expect(store.activeId == "T")
        let removed = store.removeYouTubeAccount("T", replacement: "A")
        #expect(removed == ["T"])
        store.sync(channels: [channel("A", nil, "Alex")], live: alex)
        #expect(store.activeId == "A" && store.profiles.map(\.id) == ["A"])
    }

    @Test func activatingAnUnknownProfileDoesNothing() {
        let store = ProfileStore(defaults: makeDefaults())
        store.sync(channels: channels, live: alex)
        store.activate("profile.nope")
        #expect(store.activeId == "A")
        store.activate(nil)
        #expect(store.activeId == nil)
    }

    /// A new person: named (or numbered), no accounts, not in use until switched to.
    @Test func editingAProfile() {
        let store = ProfileStore(defaults: makeDefaults())
        store.sync(channels: channels, live: alex)
        let jo = store.create(name: "  Jo  ")
        #expect(jo.name == "Jo" && jo.id.hasPrefix("profile.") && store.activeId == "A")
        #expect(store.create(name: " ").name == "Profile 5")

        store.add(sam, to: jo.id)
        store.add(alexKids, to: jo.id)
        #expect(store.profile(id: jo.id)?.mainYouTube == sam)  // the first one added
        store.setMain(alexKids, in: jo.id)
        store.remove(alexKids, from: jo.id)
        #expect(store.profile(id: jo.id)?.youtube == [sam] && store.profile(id: jo.id)?.mainYouTube == sam)

        // A renamed profile keeps its name when its channel's changes.
        store.rename("S", to: "Samantha")
        store.sync(channels: [channel("S", nil, "Sam B.")], live: alex)
        #expect(store.profile(id: "S")?.name == "Samantha")

        #expect(!store.delete("A"))  // in use
        #expect(store.delete(jo.id) && store.profile(id: jo.id) == nil)
    }
}
