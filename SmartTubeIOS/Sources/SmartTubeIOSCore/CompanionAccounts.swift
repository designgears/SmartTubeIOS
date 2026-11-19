import Foundation

// MARK: - CompanionAccounts

/// The profile in use's other YouTube accounts — every one but the live session (`AppProfile`).
/// Their subscriptions, subscribed channels and live streams are read alongside the main
/// account's and combined with them; history, likes and playback stay the main account's.
@MainActor
public final class CompanionAccounts {
    public static let shared = CompanionAccounts()

    /// Installed by the app (`AuthService`): one API per companion account, its token valid.
    public var provider: @MainActor () async -> [any InnerTubeAPIProtocol] = { [] }

    init() {}

    public func apis() async -> [any InnerTubeAPIProtocol] { await provider() }

    /// The main account's subscriptions feed with the companions' merged in (newest first).
    /// Fails only when the main account's does.
    public func subscriptions(main api: any InnerTubeAPIProtocol) async throws -> VideoGroup {
        async let companions = each { try await $0.fetchSubscriptions().videos }
        var group = try await api.fetchSubscriptions()
        group.videos = Self.mergedFeed([group.videos] + (await companions))
        return group
    }

    /// The main account's subscribed channels, then the companions' others.
    public func subscribedChannels(main api: any InnerTubeAPIProtocol) async throws -> [Channel] {
        async let companions = each { try await $0.fetchSubscribedChannels() }
        let channels = try await api.fetchSubscribedChannels()
        return Self.mergedChannels([channels] + (await companions))
    }

    /// Runs `read` against every companion account at once; failures and empty answers drop out.
    public func each<T: Sendable>(
        _ read: @escaping @Sendable (any InnerTubeAPIProtocol) async throws -> T
    ) async -> [T] {
        let apis = await apis()
        guard !apis.isEmpty else { return [] }
        return await withTaskGroup(of: (Int, T?).self) { group in
            for (index, api) in apis.enumerated() {
                group.addTask { (index, try? await read(api)) }
            }
            var results: [(Int, T)] = []
            for await (index, value) in group { if let value { results.append((index, value)) } }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    // MARK: Combining

    /// One subscriptions feed from several: newest first, each video once.
    public static func mergedFeed(_ feeds: [[Video]]) -> [Video] {
        var seen = Set<String>()
        return feeds.flatMap { $0 }
            .filter { seen.insert($0.id).inserted }
            .enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (lhs.element.publishedAt ?? .distantPast, rhs.element.publishedAt ?? .distantPast)
                return left != right ? left > right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// One channel list from several, in the main account's order, then each account's new ones.
    public static func mergedChannels(_ lists: [[Channel]]) -> [Channel] {
        var seen = Set<String>()
        return lists.flatMap { $0 }.filter { seen.insert($0.id).inserted }
    }
}

extension InnerTubeAPI {
    /// An API for a companion account: its own token and Brand Account page, and a session with
    /// no cookies, so nothing of the live account's web session goes with its requests.
    public static func companion(authToken: String, pageId: String?) -> InnerTubeAPI {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = requestTimeoutInterval
        config.timeoutIntervalForResource = 60
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        let channel = ActiveChannel()
        channel.set(pageId: pageId)
        return InnerTubeAPI(authToken: authToken, session: URLSession(configuration: config), activeChannel: channel)
    }
}
