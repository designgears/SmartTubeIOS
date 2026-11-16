import Foundation

// MARK: - HistoryBackfill

/// How far a full read of the account's YouTube history has got (see `WatchedHistorySync`).
public struct HistoryBackfill: Codable, Equatable, Sendable {
    /// Continuation token of the next page to read; nil before the read starts or once done.
    public var token: String?
    public var isComplete: Bool

    public static let notStarted = HistoryBackfill(token: nil, isComplete: false)
}

// MARK: - WatchedStoreFile

/// One account's watched data on disk: a compact JSON file per account slot in Caches.
///
/// Not UserDefaults: on tvOS that's capped at about 500 KB for the whole app, and a full
/// YouTube history runs to tens of thousands of videos. tvOS may purge Caches when space runs
/// low; the history is then simply read again (only marks for videos finished in this app,
/// which `VideoStateStore` doesn't keep, are lost).
struct WatchedStoreFile: Sendable {
    struct Contents: Codable, Equatable {
        var ids: [String] = []
        var local: [Double?] = []
        var history: [Double?] = []
        var backfill = HistoryBackfill.notStarted
    }

    let directory: URL

    static var defaultDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("WatchedHistory", isDirectory: true)
    }

    func read(_ slot: String) -> Contents? {
        guard let data = try? Data(contentsOf: url(for: slot)) else { return nil }
        return try? JSONDecoder().decode(Contents.self, from: data)
    }

    func write(_ contents: Contents, for slot: String) {
        guard let data = try? JSONEncoder().encode(contents) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(for: slot), options: .atomic)
    }

    /// Deletes a removed account's files — every channel profile of it — except `liveSlot`'s.
    func remove(accountId: String, keeping liveSlot: String?) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names {
            guard let slot = Self.slot(fromFileName: name), slot != liveSlot,
                slot == accountId || slot.hasPrefix("\(accountId).channel.")
            else { continue }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func url(for slot: String) -> URL {
        let safe = slot.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? slot
        return directory.appendingPathComponent("\(safe).json")
    }

    private static func slot(fromFileName name: String) -> String? {
        guard name.hasSuffix(".json") else { return nil }
        return String(name.dropLast(".json".count)).removingPercentEncoding
    }
}
