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
