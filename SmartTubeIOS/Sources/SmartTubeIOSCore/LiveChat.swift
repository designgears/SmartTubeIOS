import Foundation
import Observation
import os

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private let chatLog = Logger(subsystem: appSubsystem, category: "LiveChat")

// MARK: - ChatMessage

public struct ChatMessage: Identifiable, Hashable, Sendable {
    public let id: String
    public let author: String
    /// "#RRGGBB" when the author picked a color.
    public let color: String?
    public let text: String

    public init(id: String, author: String, color: String?, text: String) {
        self.id = id
        self.author = author
        self.color = color
        self.text = text
    }
}

// MARK: - LiveChatFeed

/// A live stream's chat, read-only: the newest `capacity` messages, oldest first. Twitch is
/// IRC over WebSocket with an anonymous guest nick; Kick is Centrifugo with a guest token.
/// A dropped connection is retried after `retryDelay` until `stop()`.
@MainActor
@Observable
public final class LiveChatFeed {
    public static let capacity = 120
    static let retryDelay: Duration = .seconds(3)

    public private(set) var messages: [ChatMessage] = []
    public private(set) var isConnected = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var videoId: String?

    public init() {}

    /// Chat is there for Twitch and Kick live streams.
    public static func isAvailable(for video: Video) -> Bool {
        ExternalID.parse(video.id)?.kind == .live
    }

    public func start(video: Video) {
        guard Self.isAvailable(for: video), let target = ExternalID.parse(video.id) else { return }
        guard videoId != video.id || task == nil else { return }
        stop()
        videoId = video.id
        task = Task { [weak self] in
            while !Task.isCancelled {
                let stream =
                    target.platform == .twitch
                    ? LiveChatConnection.twitch(login: target.key) : LiveChatConnection.kick(slug: target.key)
                for await event in stream {
                    guard let self else { return }
                    switch event {
                    case .connected: self.isConnected = true
                    case .message(let message): self.append(message)
                    }
                }
                self?.isConnected = false
                try? await Task.sleep(for: Self.retryDelay)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        videoId = nil
        isConnected = false
        messages = []
    }

    func append(_ message: ChatMessage) {
        messages.append(message)
        if messages.count > Self.capacity { messages.removeFirst(messages.count - Self.capacity) }
    }
}

// MARK: - Connections

enum LiveChatConnection {
    enum Event: Sendable {
        case connected
        case message(ChatMessage)
    }

    static let twitchURL = URL(string: "wss://irc-ws.chat.twitch.tv:443")!
    static let kickAPI = "https://web.kick.com/api/v1/realtime"

    /// Twitch IRC, anonymous: `justinfan<n>` reads any channel's chat.
    static func twitch(login: String) -> AsyncStream<Event> {
        run(
            prepare: { URLSession.shared.webSocketTask(with: twitchURL) },
            body: { socket, continuation in
                guard let socket else { return }
                socket.resume()
                for line in [
                    "CAP REQ :twitch.tv/tags", "PASS SCHMOOPIIE", "NICK justinfan\(Int.random(in: 10_000...99_999))",
                    "JOIN #\(login.lowercased())",
                ] {
                    try await socket.send(.string(line))
                }
                continuation.yield(.connected)
                while !Task.isCancelled {
                    guard case .string(let text) = try await socket.receive() else { continue }
                    for line in text.split(separator: "\r\n").map(String.init) {
                        if line.hasPrefix("PING") {
                            try await socket.send(.string("PONG :tmi.twitch.tv"))
                        } else if let message = LiveChatParsing.twitch(line) {
                            continuation.yield(.message(message))
                        }
                    }
                }
            })
    }

    /// Kick: the chat server and a guest token from Kick's realtime API, then Centrifugo.
    static func kick(slug: String) -> AsyncStream<Event> {
        run(
            prepare: { try await kickSocket(slug: slug) },
            body: { socket, continuation in
                guard let socket else { return }
                continuation.yield(.connected)
                while !Task.isCancelled {
                    guard case .string(let text) = try await socket.receive() else { continue }
                    for line in text.split(separator: "\n").map(String.init) {
                        if line == "{}" {
                            try await socket.send(.string("{}"))  // Centrifugo ping
                        } else if let message = LiveChatParsing.kick(line) {
                            continuation.yield(.message(message))
                        }
                    }
                }
            })
    }

    private static func kickSocket(slug: String) async throws -> URLSessionWebSocketTask? {
        guard let ids = try await KickClient.shared.chatIDs(slug: slug) else { return nil }
        let clientId = UUID().uuidString.lowercased()
        let connection = try await postJSON(
            "\(kickAPI)/channels/\(ids.channel)/chat/connection",
            [
                "client": ["id": clientId, "type": "web"],
                "capabilities": ["accepted_providers": [["provider": "centrifugo"]]],
            ])
        let auth = try await postJSON("\(kickAPI)/auth/connection", ["client_id": clientId])
        guard let url = LiveChatParsing.kickServer(connection), let token = LiveChatParsing.kickToken(auth) else {
            chatLog.error("Kick chat: no server or token")
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue("https://kick.com", forHTTPHeaderField: "Origin")
        request.setValue(KickClient.userAgent, forHTTPHeaderField: "User-Agent")
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.resume()
        try await socket.send(.string(LiveChatParsing.json(["id": 1, "connect": ["token": token, "name": "js"]])))
        try await socket.send(
            .string(LiveChatParsing.json(["id": 2, "subscribe": ["channel": "chatrooms.\(ids.chatroom).v2"]])))
        return socket
    }

    private static func postJSON(_ url: String, _ body: [String: Any]) async throws -> Data {
        guard let url = URL(string: url) else { throw ExternalStreamError.unavailable("Bad chat URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(KickClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ExternalStreamError.http(status) }
        return data
    }

    /// One connection's events; it ends when the socket fails or the stream is dropped.
    private static func run(
        prepare: @escaping @Sendable () async throws -> URLSessionWebSocketTask?,
        body: @escaping @Sendable (URLSessionWebSocketTask?, AsyncStream<Event>.Continuation) async throws -> Void
    ) -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task {
                var socket: URLSessionWebSocketTask?
                do {
                    socket = try await prepare()
                    try await body(socket, continuation)
                } catch {
                    if !Task.isCancelled {
                        chatLog.notice("chat closed: \(error.localizedDescription, privacy: .public)")
                    }
                }
                socket?.cancel(with: .goingAway, reason: nil)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Parsing

enum LiveChatParsing {
    /// `@tags :nick!nick@nick.tmi.twitch.tv PRIVMSG #channel :text`
    static func twitch(_ line: String) -> ChatMessage? {
        guard let privmsg = line.range(of: " PRIVMSG #") else { return nil }
        let afterChannel = line[privmsg.upperBound...]
        guard let textStart = afterChannel.range(of: " :") else { return nil }
        var text = String(afterChannel[textStart.upperBound...])
        // "/me" actions arrive wrapped in \u{1}ACTION ...\u{1}.
        if text.hasPrefix("\u{1}ACTION "), text.hasSuffix("\u{1}") {
            text = String(text.dropFirst(8).dropLast())
        }
        var tags: [String: String] = [:]
        if line.hasPrefix("@"), let end = line.firstIndex(of: " ") {
            for pair in line[line.index(after: line.startIndex)..<end].split(separator: ";") {
                let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if parts.count == 2 { tags[String(parts[0])] = String(parts[1]) }
            }
        }
        let prefix = line[..<privmsg.lowerBound]
        let nick = prefix.split(separator: ":").last.flatMap { $0.split(separator: "!").first }.map(String.init)
        let author = tags["display-name"].flatMap { $0.isEmpty ? nil : $0 } ?? nick ?? "?"
        return ChatMessage(
            id: tags["id"] ?? UUID().uuidString, author: author,
            color: tags["color"].flatMap { $0.isEmpty ? nil : $0 }, text: text)
    }

    /// A Centrifugo frame: `{"push":{"pub":{"data":{"event":"App\\Events\\ChatMessageEvent","data":"<json>"}}}}`.
    static func kick(_ line: String) -> ChatMessage? {
        guard let root = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            let publication = (root["push"] as? [String: Any])?["pub"] as? [String: Any],
            let envelope = publication["data"] as? [String: Any],
            (envelope["event"] as? String)?.hasSuffix("ChatMessageEvent") == true,
            let payload = (envelope["data"] as? String).flatMap({ $0.data(using: .utf8) }),
            let message = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let content = message["content"] as? String
        else { return nil }
        let sender = message["sender"] as? [String: Any]
        return ChatMessage(
            id: message["id"] as? String ?? UUID().uuidString,
            author: sender?["username"] as? String ?? "?",
            color: (sender?["identity"] as? [String: Any])?["color"] as? String,
            text: kickEmotes(content))
    }

    /// `[emote:5748001:KEKW]` -> `KEKW`.
    static func kickEmotes(_ text: String) -> String {
        text.replacing(/\[emote:\d+:([^\]]+)\]/) { String($0.output.1) }
    }

    static func kickServer(_ data: Data) -> URL? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let connections = (root["data"] as? [String: Any])?["connections"] as? [[String: Any]]
        else { return nil }
        let centrifugo = connections.first { $0["provider"] as? String == "centrifugo" }
        return ((centrifugo?["credentials"] as? [String: Any])?["url"] as? String).flatMap(URL.init(string:))
    }

    static func kickToken(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (root["data"] as? [String: Any])?["token"] as? String
    }

    static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
            let text = String(bytes: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}
