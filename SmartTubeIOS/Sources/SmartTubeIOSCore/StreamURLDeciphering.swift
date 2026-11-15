import Foundation

// `n`, `s` and `sp` are YouTube's own query-parameter names; keeping them makes the mapping
// to stream URLs obvious.
// swiftlint:disable identifier_name

// MARK: - StreamURLDeciphering

/// Solves YouTube player-JS challenges for stream URLs:
/// - `n`   — the throttling parameter on googlevideo URLs (untransformed n → throttled / 403).
/// - `sig` — the `s` value from a `signatureCipher` format (no URL at all without it).
///
/// Implemented in the app layer (`YouTubeJSSolver`, JavaScriptCore + yt-dlp EJS) and
/// registered via `StreamURLDecipherRegistry` so every `InnerTubeAPI` instance uses it.
public protocol StreamURLDeciphering: Sendable {
    /// Returns solutions keyed by challenge. Missing keys mean "could not solve".
    func solve(n: Set<String>, sig: Set<String>) async -> StreamChallengeSolutions

    /// The `signatureTimestamp` of the player JS the solver uses. Player requests must
    /// send this STS or the returned ciphers will not match the solver's player.
    func signatureTimestamp() async -> Int?
}

public struct StreamChallengeSolutions: Sendable, Equatable {
    public var n: [String: String]
    public var sig: [String: String]

    public init(n: [String: String] = [:], sig: [String: String] = [:]) {
        self.n = n
        self.sig = sig
    }

    public static let empty = StreamChallengeSolutions()
}

// MARK: - Registry

/// Process-wide decipherer. Set once at launch from the app entry point.
public enum StreamURLDecipherRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var storage: (any StreamURLDeciphering)?

    public static var current: (any StreamURLDeciphering)? {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}

// MARK: - StreamURLRewriter

/// Pure helpers that turn raw `streamingData` format dictionaries into playable URLs,
/// given a set of solved challenges. No JS, no networking — unit-testable.
public enum StreamURLRewriter {
    public struct Challenges: Equatable, Sendable {
        public var n: Set<String> = []
        public var sig: Set<String> = []
        public var isEmpty: Bool { n.isEmpty && sig.isEmpty }
    }

    /// The pieces of a `signatureCipher` / `cipher` field.
    struct Cipher: Equatable {
        let url: String
        let s: String
        let sp: String
    }

    /// Collects the `n` and `sig` challenges present in `formats`.
    /// - Parameter includeN: only clients that use the JS player (WEB, MWEB, TV, embedded)
    ///   need the n transform; applying it to Android/iOS/VR URLs breaks them.
    public static func challenges(in formats: [[String: Any]], includeN: Bool) -> Challenges {
        var result = Challenges()
        for format in formats {
            let base: String?
            if let url = format["url"] as? String {
                base = url
            } else if let cipher = cipher(of: format) {
                base = cipher.url
                result.sig.insert(cipher.s)
            } else {
                base = nil
            }
            if includeN, let base, let n = queryValue("n", in: base) {
                result.n.insert(n)
            }
        }
        return result
    }

    /// Returns the playable URL for one format, or nil when it is ciphered and unsolved.
    public static func resolvedURL(
        for format: [String: Any], solutions: StreamChallengeSolutions, includeN: Bool
    ) -> URL? {
        var urlString: String
        if let url = format["url"] as? String {
            urlString = url
        } else if let cipher = cipher(of: format) {
            guard let solved = solutions.sig[cipher.s] else { return nil }
            urlString = cipher.url + (cipher.url.contains("?") ? "&" : "?") + "\(cipher.sp)=\(encode(solved))"
        } else {
            return nil
        }
        if includeN, let n = queryValue("n", in: urlString), let solvedN = solutions.n[n] {
            urlString = replacingQueryValue("n", with: solvedN, in: urlString)
        }
        return URL(string: urlString)
    }

    // MARK: HLS playlists

    // swiftlint:disable:next force_try
    private static let hlsNPattern = try! NSRegularExpression(pattern: #"/n/([^/\s"]+)/"#)  // constant, valid pattern

    /// Distinct `/n/VALUE/` path values in an HLS playlist (master or variant).
    public static func hlsNChallenges(in playlist: String) -> Set<String> {
        let range = NSRange(playlist.startIndex..., in: playlist)
        return Set(
            hlsNPattern.matches(in: playlist, range: range).compactMap { match in
                Range(match.range(at: 1), in: playlist).map { String(playlist[$0]) }
            })
    }

    /// Replaces every `/n/OLD/` with `/n/NEW/` for each solved value.
    public static func replacingHLSN(in playlist: String, solutions: [String: String]) -> String {
        var text = playlist
        for (old, new) in solutions where old != new {
            text = text.replacingOccurrences(of: "/n/\(old)/", with: "/n/\(new)/")
        }
        return text
    }

    // MARK: Internals

    static func cipher(of format: [String: Any]) -> Cipher? {
        guard let raw = (format["signatureCipher"] as? String) ?? (format["cipher"] as? String) else {
            return nil
        }
        var comps = URLComponents()
        comps.percentEncodedQuery = raw
        let items = comps.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let url = value("url"), let s = value("s") else { return nil }
        return Cipher(url: url, s: s, sp: value("sp") ?? "signature")
    }

    /// Percent-decoded value of query parameter `name`, or nil.
    static func queryValue(_ name: String, in urlString: String) -> String? {
        guard let comps = URLComponents(string: urlString) else { return nil }
        return comps.queryItems?.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Replaces parameter `name`'s value while leaving every other parameter's
    /// encoding untouched (googlevideo signs over the exact query text).
    static func replacingQueryValue(_ name: String, with value: String, in urlString: String) -> String {
        guard var comps = URLComponents(string: urlString), var items = comps.percentEncodedQueryItems else {
            return urlString
        }
        for index in items.indices where items[index].name == name {
            items[index].value = encode(value)
        }
        comps.percentEncodedQueryItems = items
        return comps.string ?? urlString
    }

    private static let valueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#")
        return set
    }()

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: valueAllowed) ?? value
    }
}

// swiftlint:enable identifier_name
