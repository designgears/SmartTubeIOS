import Foundation

// MARK: - Subscribed channels from the TV Subscriptions page

extension InnerTubeAPI {
    /// The channels in the TV Subscriptions page's side list (`FEsubscriptions`): an "All" tab,
    /// then one tab per subscribed channel with its name and avatar, in YouTube's order.
    ///
    /// This is the whole subscription list. The TV guide, used before, comes back without any
    /// channels for some accounts (seen for a Brand Account), and the fallback after it only
    /// found channels with a video on the feed's first page.
    static func parseSubscriptionTabs(from json: [String: Any]) -> [Channel] {
        guard let section = firstValue(forKey: "tvSecondaryNavSectionRenderer", in: json) as? [String: Any],
            let tabs = section["tabs"] as? [[String: Any]]
        else { return [] }
        var seen = Set<String>()
        return tabs.compactMap { tab in
            guard let tab = tab["tabRenderer"] as? [String: Any],
                let browse = (tab["endpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any],
                let params = browse["params"] as? String,
                let id = channelId(inTabParams: params),
                seen.insert(id).inserted
            else { return nil }  // "All" has no params
            let thumbnails = (tab["thumbnail"] as? [String: Any])?["thumbnails"] as? [[String: Any]]
            let avatar = (thumbnails?.last?["url"] as? String).flatMap {
                URL(string: $0.hasPrefix("//") ? "https:\($0)" : $0)
            }
            return Channel(id: id, title: tab["title"] as? String ?? "", thumbnailURL: avatar)
        }
    }

    /// A channel tab's `params` is a URL-escaped, base64 protobuf that wraps the channel's
    /// `UC…` ID as plain bytes.
    static func channelId(inTabParams params: String) -> String? {
        var base64 = (params.removingPercentEncoding ?? params)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        // Latin-1: every byte maps to a character, so the protobuf framing can't fail the read.
        guard let data = Data(base64Encoded: base64), let text = String(bytes: data, encoding: .isoLatin1) else {
            return nil
        }
        return text.firstMatch(of: /UC[A-Za-z0-9_-]{22}/).map { String($0.output) }
    }

    private static func firstValue(forKey key: String, in value: Any, depth: Int = 0) -> Any? {
        guard depth < 12 else { return nil }
        if let dict = value as? [String: Any] {
            if let found = dict[key] { return found }
            for child in dict.values {
                if let found = firstValue(forKey: key, in: child, depth: depth + 1) { return found }
            }
        } else if let list = value as? [Any] {
            for child in list {
                if let found = firstValue(forKey: key, in: child, depth: depth + 1) { return found }
            }
        }
        return nil
    }
}
