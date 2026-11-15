import Foundation
import Testing

@testable import SmartTubeIOSCore

extension ActiveChannelSuites {
    /// Each store swaps its own data with `AccountScope.exchange` (park the live value under
    /// the outgoing account, take the incoming account's). These cover that contract.
    @Suite("AccountScope — per-account on-device data", .serialized)
    @MainActor
    struct AccountScopeTests {
        private let key = "st_video_states"

        private func makeDefaults() -> UserDefaults {
            // swiftlint:disable:next force_unwrapping
            UserDefaults(suiteName: "account-scope-\(UUID().uuidString)")!  // a fresh suite name always works
        }

        /// Store-side simulation: exchange the live value and write the result back as live.
        private func switchStore(_ defaults: UserDefaults, from outgoing: String?, to incoming: String) {
            let next = AccountScope.exchange(
                key: key, current: defaults.object(forKey: key), outgoing: outgoing, incoming: incoming,
                defaults: defaults)
            if let next { defaults.set(next, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        /// Data saved before account scoping can't be attributed, so on first run it must
        /// not be handed to whoever is signed in.
        @Test func firstRunDiscardsUnattributedData() {
            let defaults = makeDefaults()
            defaults.set(Data("old".utf8), forKey: key)

            switchStore(defaults, from: nil, to: "A")

            #expect(defaults.object(forKey: key) == nil)
            #expect(!AccountScope.hasSavedData("A", defaults: defaults))
        }

        @Test func newAccountStartsEmpty() {
            let defaults = makeDefaults()
            defaults.set(Data("A".utf8), forKey: key)

            switchStore(defaults, from: "A", to: "B")

            #expect(defaults.object(forKey: key) == nil, "B must not see A's data")
            #expect(defaults.data(forKey: AccountScope.slotKey(key, slot: "A")) == Data("A".utf8))
        }

        @Test func switchingBackRestoresEachAccountsData() {
            let defaults = makeDefaults()
            defaults.set(Data("A".utf8), forKey: key)
            switchStore(defaults, from: "A", to: "B")
            defaults.set(Data("B".utf8), forKey: key)

            switchStore(defaults, from: "B", to: "A")
            #expect(defaults.data(forKey: key) == Data("A".utf8))

            switchStore(defaults, from: "A", to: "B")
            #expect(defaults.data(forKey: key) == Data("B".utf8))
        }

        @Test func guestHasItsOwnData() {
            let defaults = makeDefaults()
            defaults.set(Data("A".utf8), forKey: key)

            switchStore(defaults, from: "A", to: AccountScope.guestSlot)
            #expect(defaults.object(forKey: key) == nil)
            defaults.set(Data("guest".utf8), forKey: key)

            switchStore(defaults, from: AccountScope.guestSlot, to: "A")
            #expect(defaults.data(forKey: key) == Data("A".utf8))
            switchStore(defaults, from: "A", to: AccountScope.guestSlot)
            #expect(defaults.data(forKey: key) == Data("guest".utf8))
        }

        @Test func forgetDeletesARemovedAccountsParkedData() {
            let defaults = makeDefaults()
            defaults.set(Data("A".utf8), forKey: key)
            switchStore(defaults, from: "A", to: "B")
            defaults.set("B", forKey: AccountScope.currentSlotKey)

            AccountScope.forget("A", defaults: defaults)

            #expect(!AccountScope.hasSavedData("A", defaults: defaults))
        }

        @Test func forgetRemovesEveryChannelProfileOfTheAccount() {
            let defaults = makeDefaults()
            for slot in ["A", "A.channel.p1", "A.channel.p2", "B"] {
                defaults.set(Data(slot.utf8), forKey: AccountScope.slotKey(key, slot: slot))
            }
            defaults.set("B", forKey: AccountScope.currentSlotKey)

            AccountScope.forget("A", defaults: defaults)

            #expect(!AccountScope.hasSavedData("A", defaults: defaults))
            #expect(!AccountScope.hasSavedData("A.channel.p1", defaults: defaults))
            #expect(!AccountScope.hasSavedData("A.channel.p2", defaults: defaults))
            #expect(AccountScope.hasSavedData("B", defaults: defaults))
        }

        @Test func forgetNeverDeletesTheLiveAccount() {
            let defaults = makeDefaults()
            defaults.set(Data("A-parked".utf8), forKey: AccountScope.slotKey(key, slot: "A"))
            defaults.set("A", forKey: AccountScope.currentSlotKey)

            AccountScope.forget("A", defaults: defaults)

            #expect(AccountScope.hasSavedData("A", defaults: defaults))
        }
    }
}
