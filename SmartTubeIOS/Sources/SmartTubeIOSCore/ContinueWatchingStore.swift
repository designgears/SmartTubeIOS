import Foundation

// MARK: - ContinueWatchingStore
//
// Videos the user removed from Continue Watching. Per account (swapped by `AccountScope`).
// Removing only hides the card: the saved position stays, so opening the video elsewhere
// still resumes it. Watching it again after the removal brings it back.

public actor ContinueWatchingStore: UserDefaultsBackedStore {

    public static let shared = ContinueWatchingStore()

    static let defaultsKey = "st_continue_watching_removed"
    private static let maxEntries = 500

    /// Video id → when it was removed.
    private var removed: [String: Date] = [:]
    let defaults: UserDefaults

    private init() {
        self.defaults = .standard
        if let loaded = Self.loadFrom(.standard) { removed = loaded }
    }

    /// Isolated store for unit tests (`suiteName` like `"test-\(UUID().uuidString)"`).
    init(suiteName: String) {
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        if let loaded = Self.loadFrom(self.defaults) { removed = loaded }
    }

    // MARK: - Public API

    /// Takes `videoId` off Continue Watching until it's watched again.
    public func remove(videoId: String, at date: Date = Date()) {
        removed[videoId] = date
        prune()
        persist()
    }

    /// Whether `videoId` stays off Continue Watching: it was removed and hasn't been watched
    /// since. `lastWatched` is when its position was last saved (`VideoStateStore`).
    public func isRemoved(_ videoId: String, lastWatched: Date?) -> Bool {
        guard let removedAt = removed[videoId] else { return false }
        guard let lastWatched else { return true }
        return lastWatched <= removedAt
    }

    /// The first of `history` (newest first) not removed from Continue Watching — what a
    /// "Continue Watching" shortcut opens.
    public func mostRecent(in history: [Video], videoStates: VideoStateStore = .shared) async -> Video? {
        for video in history {
            let lastWatched = await videoStates.state(for: video.id)?.timestamp
            if !isRemoved(video.id, lastWatched: lastWatched) { return video }
        }
        return nil
    }

    // MARK: - UserDefaultsBackedStore

    static var emptyValue: [String: Date] { [:] }
    func encodedValue() -> [String: Date] { removed }
    func decodeValue(_ decoded: [String: Date]) { removed = decoded }

    private func prune() {
        guard removed.count > Self.maxEntries else { return }
        let oldest = removed.sorted { $0.value < $1.value }.prefix(removed.count - Self.maxEntries)
        for (id, _) in oldest { removed.removeValue(forKey: id) }
    }
}
