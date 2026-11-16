import Foundation

// MARK: - Unavailable variant pruning
//
// YouTube masters sometimes list a variant whose media playlist 404s (seen: the 240p avc1
// variant of some videos). AVPlayer starts on the first variant and, when that playlist
// can't load, fails the whole item instead of moving on — which sent playback down to the
// 360p muxed fallback. The HLS proxy checks the playlists a master references and drops the
// broken ones with these helpers before AVPlayer sees the master.

/// The media playlists a multivariant (master) playlist references: each variant's URI and each `#EXT-X-MEDIA` URI.
public func hlsMultivariantPlaylistURIs(_ manifest: String) -> [String] {
    var uris: [String] = []
    var expectVariantURI = false
    for line in manifest.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { continue }
        if trimmed.hasPrefix("#EXT-X-STREAM-INF:") {
            expectVariantURI = true
        } else if trimmed.hasPrefix("#EXT-X-MEDIA:") {
            if let uri = extractQuotedHLSAttribute("URI", from: trimmed) { uris.append(uri) }
        } else if !trimmed.hasPrefix("#"), expectVariantURI {
            uris.append(trimmed)
            expectVariantURI = false
        }
    }
    return uris
}

/// Removes the variants and renditions whose playlist URI is in `unavailable`. A variant
/// whose `AUDIO` group lost every rendition goes too, since AVPlayer can't play it.
public func removingHLSPlaylists(_ unavailable: Set<String>, from manifest: String) -> String {
    guard !unavailable.isEmpty else { return manifest }
    let lines = manifest.components(separatedBy: .newlines)

    // Audio groups that still have a playable rendition, and those that had any at all.
    var groupsWithRenditions: Set<String> = []
    var allGroups: Set<String> = []
    for line in lines where line.hasPrefix("#EXT-X-MEDIA:") {
        guard let group = extractQuotedHLSAttribute("GROUP-ID", from: line) else { continue }
        allGroups.insert(group)
        let uri = extractQuotedHLSAttribute("URI", from: line)
        if uri.map({ !unavailable.contains($0) }) ?? true { groupsWithRenditions.insert(group) }
    }
    let emptiedGroups = allGroups.subtracting(groupsWithRenditions)

    var output: [String] = []
    var pendingVariant: String?
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#EXT-X-MEDIA:"),
            let uri = extractQuotedHLSAttribute("URI", from: trimmed), unavailable.contains(uri)
        {
            continue
        }
        if trimmed.hasPrefix("#EXT-X-STREAM-INF:") {
            pendingVariant = line
            continue
        }
        if let variant = pendingVariant, !trimmed.isEmpty, !trimmed.hasPrefix("#") {
            pendingVariant = nil
            let audioGroup = extractQuotedHLSAttribute("AUDIO", from: variant)
            let lostAudio = audioGroup.map { emptiedGroups.contains($0) } ?? false
            if !unavailable.contains(trimmed), !lostAudio {
                output.append(variant)
                output.append(line)
            }
            continue
        }
        output.append(line)
    }
    return output.joined(separator: "\n")
}

// MARK: - Live variants

/// A YouTube live multivariant playlist cut down to the variants that match its best one in
/// audio codec and frame rate.
///
/// YouTube's live ladders mix them — 144p and 240p carry HE-AAC audio (`mp4a.40.5`) where the
/// rest carry AAC-LC, and 144p runs at 15 fps against 30 — and list 144p first, so playback
/// starts there and switches up. Each switch changes the audio codec and frame rate under a
/// running stream (Apple's HLS rules ask variants not to), and on Apple TV the video fell
/// steadily behind the audio. Videos and other playlists are returned as they are.
public func consistentLiveVariants(_ manifest: String) -> String {
    guard manifest.contains("yt_live_broadcast") || manifest.contains("/live/1/") else { return manifest }
    let lines = manifest.components(separatedBy: "\n")
    struct Variant {
        let index: Int
        let bandwidth: Int
        let audio: String?
        let frameRate: String?
    }
    let variants: [Variant] = lines.indices.compactMap { index in
        let line = lines[index]
        guard line.hasPrefix("#EXT-X-STREAM-INF:") else { return nil }
        return Variant(
            index: index,
            bandwidth: hlsAttribute("BANDWIDTH", in: line).flatMap { Int($0) } ?? 0,
            audio: hlsAttribute("CODECS", in: line)?.split(separator: ",").first { $0.hasPrefix("mp4a") }.map(String.init),
            frameRate: hlsAttribute("FRAME-RATE", in: line))
    }
    guard let best = variants.max(by: { $0.bandwidth < $1.bandwidth }) else { return manifest }
    let dropped = Set(
        variants.filter { $0.audio != best.audio || $0.frameRate != best.frameRate }.map(\.index))
    guard !dropped.isEmpty else { return manifest }
    var output: [String] = []
    var skipURI = false
    for (index, line) in lines.enumerated() {
        if dropped.contains(index) {
            skipURI = true
            continue
        }
        if skipURI, !line.hasPrefix("#"), !line.trimmingCharacters(in: .whitespaces).isEmpty {
            skipURI = false
            continue
        }
        output.append(line)
    }
    return output.joined(separator: "\n")
}

/// The value of `name` in an HLS attribute list (quotes removed).
private func hlsAttribute(_ name: String, in line: String) -> String? {
    let pattern = #"(?:^|[:,])"# + name + #"=("[^"]*"|[^,]*)"#
    guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
    let match = line[range]
    guard let equals = match.firstIndex(of: "=") else { return nil }
    return String(match[match.index(after: equals)...]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
}
