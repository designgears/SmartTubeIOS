import Foundation
import os

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let kickLog = Logger(subsystem: appSubsystem, category: "Kick")

// MARK: - KickClient

/// Kick's public website API for channels, live streams, past broadcasts and search; the
/// streams themselves are HLS (Amazon IVS). No account: Kick's own API needs a registered
/// app, and its sign-in has no TV flow, so followed Kick channels are kept on the device
/// (`ExternalFollowStore`).
///
/// Kick sits behind Cloudflare, which answers a browser-like User-Agent.
public actor KickClient {
    public static let shared = KickClient()

    static let base = "https://kick.com/api"
    static let userAgent =
        "Mozilla/5.0 (AppleTV; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)"

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// The channel, with its live stream when live (nil for an unknown slug).
    public func channel(slug: String) async throws -> ExternalChannel? {
        guard let data = try await get("/v2/channels/\(Self.escaped(slug))", allowNotFound: true) else { return nil }
        guard var channel = Self.parseChannel(data) else { return nil }
        // The channel answer has no live thumbnail; the livestream answer does.
        if channel.live != nil, let live = try? await livestream(slug: slug) { channel.live = live }
        return channel
    }

    /// The channel's numeric id and its chat room, for live chat.
    public func chatIDs(slug: String) async throws -> (channel: Int, chatroom: Int)? {
        guard let data = try await get("/v2/channels/\(Self.escaped(slug))", allowNotFound: true),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let channel = root["id"] as? Int,
            let chatroom = (root["chatroom"] as? [String: Any])?["id"] as? Int
        else { return nil }
        return (channel, chatroom)
    }

    /// The channel's live stream, nil when offline.
    public func livestream(slug: String) async throws -> Video? {
        guard let data = try await get("/v2/channels/\(Self.escaped(slug))/livestream", allowNotFound: true) else {
            return nil
        }
        return Self.parseLivestream(data, slug: slug)
    }

    /// Past broadcasts, newest first.
    public func videos(slug: String) async throws -> [Video] {
        guard let data = try await get("/v2/channels/\(Self.escaped(slug))/videos", allowNotFound: true) else {
            return []
        }
        return Self.parseVideos(data, slug: slug)
    }

    /// Channels matching `text`. Kick's search answer has no avatars and no stream details, so
    /// the first `detailedResults` are looked up in full.
    public func search(_ text: String) async throws -> [ExternalChannel] {
        var components = URLComponents(string: "\(Self.base)/search")
        components?.queryItems = [URLQueryItem(name: "searched_word", value: text)]
        guard let url = components?.url, let data = try await get(url, allowNotFound: false) else { return [] }
        var found = Self.parseSearch(data)
        let slugs = found.prefix(Self.detailedResults).compactMap { ExternalID.parse($0.id)?.key }
        let detailed = await withTaskGroup(of: ExternalChannel?.self) { group in
            for slug in slugs { group.addTask { try? await self.channel(slug: slug) } }
            var byId: [String: ExternalChannel] = [:]
            for await channel in group { if let channel { byId[channel.id] = channel } }
            return byId
        }
        for index in found.indices { if let full = detailed[found[index].id] { found[index] = full } }
        return found
    }

    static let detailedResults = 12

    /// The HLS master URL for a live stream or past broadcast.
    public func playbackURL(for target: ExternalID.Parsed) async throws -> URL {
        let path =
            target.kind == .vod ? "/v1/video/\(Self.escaped(target.key))" : "/v2/channels/\(Self.escaped(target.key))"
        guard let data = try await get(path, allowNotFound: true),
            let url = Self.parsePlaybackURL(data, vod: target.kind == .vod)
        else {
            throw ExternalStreamError.unavailable(
                target.kind == .vod ? "This Kick broadcast isn't available." : "This Kick channel isn't live.")
        }
        return url
    }

    // MARK: Requests

    private func get(_ path: String, allowNotFound: Bool) async throws -> Data? {
        guard let url = URL(string: Self.base + path) else { return nil }
        return try await get(url, allowNotFound: allowNotFound)
    }

    private func get(_ url: URL, allowNotFound: Bool) async throws -> Data? {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404, allowNotFound { return nil }
        guard (200..<300).contains(status) else {
            kickLog.error("HTTP \(status, privacy: .public) for \(url.path, privacy: .public)")
            throw ExternalStreamError.http(status)
        }
        return data
    }

    static func escaped(_ text: String) -> String {
        text.lowercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? text
    }
}

// MARK: - Parsing

extension KickClient {
    static func parseChannel(_ data: Data) -> ExternalChannel? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return channel(root)
    }

    /// A channel object (channel page or search result).
    static func channel(_ root: [String: Any]) -> ExternalChannel? {
        guard let slug = root["slug"] as? String, !slug.isEmpty else { return nil }
        let user = root["user"] as? [String: Any]
        let name = user?["username"] as? String ?? slug
        let followers = root["followers_count"] as? Int ?? root["followersCount"] as? Int
        let channel = Channel(
            id: ExternalID.channel(.kick, slug), title: name,
            description: (user?["bio"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            thumbnailURL: (user?["profile_pic"] as? String).flatMap(URL.init(string:)),
            subscriberCount: followers.map { "\(compactCount($0)) followers" })
        var live: Video?
        if let stream = root["livestream"] as? [String: Any], stream["is_live"] as? Bool ?? true {
            let banner = (root["banner_image"] as? [String: Any])?["url"] as? String
            live = liveVideo(stream, slug: slug, name: name, fallbackThumbnail: banner)
        } else if root["isLive"] as? Bool == true {
            // Search results only say whether the channel is live.
            live = Video(
                id: ExternalID.live(.kick, slug), title: name, channelTitle: name,
                channelId: ExternalID.channel(.kick, slug), thumbnailURL: channel.thumbnailURL, isLive: true)
        }
        let chatroom = (root["chatroom"] as? [String: Any])?["id"] as? Int
        return ExternalChannel(channel: channel, live: live, chatroomID: chatroom)
    }

    /// `livestream` answer: `{"data": {...}}`, or `{"data": null}` when offline.
    static func parseLivestream(_ data: Data, slug: String) -> Video? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let stream = root["data"] as? [String: Any]
        else { return nil }
        return liveVideo(stream, slug: slug, name: nil, fallbackThumbnail: nil)
    }

    static func liveVideo(_ stream: [String: Any], slug: String, name: String?, fallbackThumbnail: String?) -> Video {
        let thumbnail = ((stream["thumbnail"] as? [String: Any])?["src"] as? String) ?? fallbackThumbnail
        var video = Video(
            id: ExternalID.live(.kick, slug), title: stream["session_title"] as? String ?? name ?? slug,
            channelTitle: name ?? slug, channelId: ExternalID.channel(.kick, slug),
            thumbnailURL: thumbnail.flatMap(URL.init(string:)),
            viewCount: stream["viewer_count"] as? Int ?? stream["viewers"] as? Int,
            publishedAt: ((stream["start_time"] ?? stream["created_at"]) as? String).flatMap(parseDate), isLive: true)
        let category =
            ((stream["category"] as? [String: Any])?["name"] as? String)
            ?? ((stream["categories"] as? [[String: Any]])?.first?["name"] as? String)
        if let category { video.badges = [category] }
        return video
    }

    static func parseVideos(_ data: Data, slug: String) -> [Video] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let uuid = (item["video"] as? [String: Any])?["uuid"] as? String,
                item["is_live"] as? Bool != true
            else { return nil }
            let date = ((item["start_time"] ?? item["created_at"]) as? String).flatMap(parseDate)
            let name = ((item["channel"] as? [String: Any])?["user"] as? [String: Any])?["username"] as? String
            return Video(
                id: ExternalID.vod(.kick, uuid), title: item["session_title"] as? String ?? "",
                channelTitle: name ?? slug, channelId: ExternalID.channel(.kick, slug),
                thumbnailURL: ((item["thumbnail"] as? [String: Any])?["src"] as? String).flatMap(URL.init(string:)),
                // Kick gives the length in milliseconds.
                duration: (item["duration"] as? Double).map { $0 / 1000 },
                viewCount: item["views"] as? Int, publishedAt: date, publishedTimeText: date.map(relativeTimeText))
        }
    }

    static func parseSearch(_ data: Data) -> [ExternalChannel] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let channels = root["channels"] as? [[String: Any]]
        else { return [] }
        return channels.compactMap(channel)
    }

    static func parsePlaybackURL(_ data: Data, vod: Bool) -> URL? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if vod { return (root["source"] as? String).flatMap(URL.init(string:)) }
        guard root["livestream"] is [String: Any] else { return nil }
        return (root["playback_url"] as? String).flatMap(URL.init(string:))
    }

    /// Kick dates: "2026-11-19 16:30:50" (UTC) or ISO 8601 with microseconds.
    static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: text) { return date }
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ"
        return formatter.date(from: text) ?? TwitchClient.parseDate(text)
    }
}
