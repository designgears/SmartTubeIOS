import Foundation
import os

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let twitchLog = Logger(subsystem: appSubsystem, category: "Twitch")

// MARK: - ExternalChannel

/// A Twitch or Kick channel, with its stream when it's live.
public struct ExternalChannel: Identifiable, Hashable, Sendable {
    public var channel: Channel
    /// The live stream (a `Video` with `isLive`), nil when offline.
    public var live: Video?
    /// Kick only: the chat room to join for live chat.
    public var chatroomID: Int?

    public var id: String { channel.id }

    public init(channel: Channel, live: Video? = nil, chatroomID: Int? = nil) {
        self.channel = channel
        self.live = live
        self.chatroomID = chatroomID
    }
}

// MARK: - TwitchClient

/// Twitch's public web API (GQL) for channels, live streams, past broadcasts and search,
/// and Twitch's HLS (usher) for playback. Needs no account: it uses the client ID Twitch's
/// own website uses, as other players do. Followed channels come from `TwitchAccount`.
///
/// Non-subscribers get Twitch's own ads inside the stream.
public actor TwitchClient {
    public static let shared = TwitchClient()

    static let webClientID = "kimne78kx3ncx6brgo4mv6wki5h1ko"
    static let gqlURL = URL(string: "https://gql.twitch.tv/gql")!
    /// GQL accepts at most 100 logins per `users` lookup.
    static let loginsPerRequest = 100

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Channels

    /// The channels for `logins`, each with its live stream when live; unknown logins are left out.
    public func channels(logins: [String]) async throws -> [ExternalChannel] {
        var result: [ExternalChannel] = []
        let unique = Array(Set(logins.map { $0.lowercased() })).sorted()
        for start in stride(from: 0, to: unique.count, by: Self.loginsPerRequest) {
            let batch = Array(unique[start..<min(start + Self.loginsPerRequest, unique.count)])
            let data = try await gql(Self.usersQuery(batch))
            result += Self.parseUsers(data)
        }
        return result
    }

    public func channel(login: String) async throws -> ExternalChannel? {
        try await channels(logins: [login]).first
    }

    /// Past broadcasts, newest first; `cursor` continues from the last page.
    public func videos(login: String, after cursor: String? = nil) async throws -> (videos: [Video], cursor: String?) {
        let after = cursor.map { ", after: \(Self.quoted($0))" } ?? ""
        let query = """
            query { user(login: \(Self.quoted(login.lowercased()))) { login displayName \
            videos(first: 30, type: ARCHIVE, sort: TIME\(after)) { edges { cursor node { \(Self.videoFields) } } \
            pageInfo { hasNextPage } } } }
            """
        return Self.parseVideos(try await gql(query))
    }

    public func search(_ text: String) async throws -> [ExternalChannel] {
        let query = """
            query { searchFor(userQuery: \(Self.quoted(text)), platform: "web", target: { index: CHANNEL }) { \
            channels { edges { item { ... on User { \(Self.userFields) } } } } } }
            """
        return Self.parseSearch(try await gql(query))
    }

    // MARK: Playback

    /// A fresh HLS master URL for a live stream or past broadcast (its token expires within
    /// minutes, so ask right before playing).
    public func playbackURL(for target: ExternalID.Parsed) async throws -> URL {
        let isVod = target.kind == .vod
        let body: [String: Any] = [
            "query": Self.playbackTokenQuery,
            "variables": [
                "login": isVod ? "" : target.key, "isLive": !isVod, "vodID": isVod ? target.key : "", "isVod": isVod,
            ],
        ]
        let data = try await gql(body: body)
        guard let token = Self.parsePlaybackToken(data, vod: isVod) else {
            throw ExternalStreamError.unavailable("Twitch didn't give a playback token.")
        }
        return Self.usherURL(for: target, token: token)
    }

    // MARK: Requests

    private func gql(_ query: String) async throws -> Data {
        try await gql(body: ["query": query])
    }

    private func gql(body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: Self.gqlURL)
        request.httpMethod = "POST"
        request.setValue(Self.webClientID, forHTTPHeaderField: "Client-Id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            twitchLog.error("GQL HTTP \(status, privacy: .public)")
            throw ExternalStreamError.http(status)
        }
        return data
    }
}

// MARK: - Queries and parsing

extension TwitchClient {
    static let userFields = """
        id login displayName profileImageURL(width: 300) description followers { totalCount } \
        stream { id title viewersCount createdAt game { displayName } previewImageURL(width: 640, height: 360) }
        """
    static let videoFields = """
        id title lengthSeconds createdAt viewCount previewThumbnailURL(width: 640, height: 360) \
        owner { login displayName }
        """
    static let playbackTokenQuery = """
        query PlaybackAccessToken($login: String!, $isLive: Boolean!, $vodID: ID!, $isVod: Boolean!) { \
        streamPlaybackAccessToken(channelName: $login, params: { platform: "web", playerBackend: "mediaplayer", \
        playerType: "site" }) @include(if: $isLive) { value signature } \
        videoPlaybackAccessToken(id: $vodID, params: { platform: "web", playerBackend: "mediaplayer", \
        playerType: "site" }) @include(if: $isVod) { value signature } }
        """

    static func usersQuery(_ logins: [String]) -> String {
        "query { users(logins: [\(logins.map(quoted).joined(separator: ", "))]) { \(userFields) } }"
    }

    /// A GraphQL string literal (JSON escaping is GraphQL-compatible for these values).
    static func quoted(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
            let array = String(bytes: data, encoding: .utf8)
        else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }

    struct PlaybackToken: Equatable {
        let value: String
        let signature: String
    }

    static func usherURL(for target: ExternalID.Parsed, token: PlaybackToken) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "usher.ttvnw.net"
        components.path =
            target.kind == .vod ? "/vod/\(target.key).m3u8" : "/api/channel/hls/\(target.key.lowercased()).m3u8"
        components.queryItems = [
            URLQueryItem(name: "sig", value: token.signature),
            URLQueryItem(name: "token", value: token.value),
            URLQueryItem(name: "allow_source", value: "true"),
            URLQueryItem(name: "allow_audio_only", value: "true"),
            URLQueryItem(name: "p", value: String(Int.random(in: 1_000_000...9_999_999))),
        ]
        // URLComponents leaves "+" alone; the token is JSON, so escape what the query needs.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!  // swiftlint:disable:this force_unwrapping
    }

    static func parsePlaybackToken(_ data: Data, vod: Bool) -> PlaybackToken? {
        let key = vod ? "videoPlaybackAccessToken" : "streamPlaybackAccessToken"
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = (root["data"] as? [String: Any])?[key] as? [String: Any],
            let value = token["value"] as? String, let signature = token["signature"] as? String
        else { return nil }
        return PlaybackToken(value: value, signature: signature)
    }

    static func parseUsers(_ data: Data) -> [ExternalChannel] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let users = (root["data"] as? [String: Any])?["users"] as? [Any]
        else { return [] }
        return users.compactMap { ($0 as? [String: Any]).flatMap(channel) }
    }

    static func parseSearch(_ data: Data) -> [ExternalChannel] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let searchFor = (root["data"] as? [String: Any])?["searchFor"] as? [String: Any],
            let edges = (searchFor["channels"] as? [String: Any])?["edges"] as? [[String: Any]]
        else { return [] }
        return edges.compactMap { ($0["item"] as? [String: Any]).flatMap(channel) }
    }

    static func parseVideos(_ data: Data) -> (videos: [Video], cursor: String?) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let user = (root["data"] as? [String: Any])?["user"] as? [String: Any],
            let videos = user["videos"] as? [String: Any],
            let edges = videos["edges"] as? [[String: Any]]
        else { return ([], nil) }
        let parsed = edges.compactMap { ($0["node"] as? [String: Any]).flatMap(video) }
        let hasNext = (videos["pageInfo"] as? [String: Any])?["hasNextPage"] as? Bool ?? false
        return (parsed, hasNext ? edges.last?["cursor"] as? String : nil)
    }

    /// A GQL `User` as a channel, with its stream when live.
    static func channel(_ user: [String: Any]) -> ExternalChannel? {
        guard let login = user["login"] as? String, !login.isEmpty else { return nil }
        let name = user["displayName"] as? String ?? login
        let followers = (user["followers"] as? [String: Any])?["totalCount"] as? Int
        let channel = Channel(
            id: ExternalID.channel(.twitch, login), title: name,
            description: (user["description"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            thumbnailURL: (user["profileImageURL"] as? String).flatMap(URL.init(string:)),
            subscriberCount: followers.map { "\(compactCount($0)) followers" })
        let live = (user["stream"] as? [String: Any]).flatMap { liveVideo($0, login: login, name: name) }
        return ExternalChannel(channel: channel, live: live)
    }

    static func liveVideo(_ stream: [String: Any], login: String, name: String) -> Video? {
        var video = Video(
            id: ExternalID.live(.twitch, login), title: stream["title"] as? String ?? name, channelTitle: name,
            channelId: ExternalID.channel(.twitch, login),
            thumbnailURL: (stream["previewImageURL"] as? String).flatMap(URL.init(string:)),
            viewCount: stream["viewersCount"] as? Int,
            publishedAt: (stream["createdAt"] as? String).flatMap(parseDate), isLive: true)
        if let game = (stream["game"] as? [String: Any])?["displayName"] as? String { video.badges = [game] }
        return video
    }

    static func video(_ node: [String: Any]) -> Video? {
        guard let id = node["id"] as? String, !id.isEmpty else { return nil }
        let owner = node["owner"] as? [String: Any]
        let login = owner?["login"] as? String
        let date = (node["createdAt"] as? String).flatMap(parseDate)
        return Video(
            id: ExternalID.vod(.twitch, id), title: node["title"] as? String ?? "",
            channelTitle: owner?["displayName"] as? String ?? login ?? "",
            channelId: login.map { ExternalID.channel(.twitch, $0) },
            thumbnailURL: (node["previewThumbnailURL"] as? String).flatMap(URL.init(string:)),
            duration: (node["lengthSeconds"] as? Int).map(TimeInterval.init), viewCount: node["viewCount"] as? Int,
            publishedAt: date, publishedTimeText: date.map(relativeTimeText))
    }

    static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }
}

// MARK: - Shared

public enum ExternalStreamError: Error, LocalizedError, Equatable {
    case http(Int)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .http(let status): "The server answered HTTP \(status)."
        case .unavailable(let reason): reason
        }
    }
}

/// "3 days ago" for a past broadcast's date (cards show `publishedTimeText`).
func relativeTimeText(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
}
