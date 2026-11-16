import Foundation

// MARK: - Relative age

/// "9 hours ago", "9h ago", "4mo ago", "Streamed 2 days ago" — how long ago something was
/// published, in YouTube's long or compact form.
public struct RelativeAge: Equatable, Sendable {
    public enum Unit: String, Sendable {
        case second, minute, hour, day, week, month, year

        var seconds: TimeInterval {
            switch self {
            case .second: 1
            case .minute: 60
            case .hour: 3_600
            case .day: 86_400
            case .week: 7 * 86_400
            case .month: 30 * 86_400
            case .year: 365 * 86_400
            }
        }
    }

    public let value: Int
    public let unit: Unit
    /// "Streamed", "Premiered" or "Started", when the text had one.
    public let prefix: String?

    // Longer spellings first: "mo" must win over "m" (minutes), "mins" over "m".
    private static let pattern = try? NSRegularExpression(
        pattern: #"(?:^|\s)(?:(streamed|premiered|started)\s+)?(\d+)\s*"#
            + #"(seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|weeks?|wks?|months?|mos?|years?|yrs?|s|m|h|d|w|y)\s+ago\b"#,
        options: .caseInsensitive)

    /// Finds an age anywhere in `text`.
    public init?(_ text: String) {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = Self.pattern?.firstMatch(in: text, range: range),
            let valueRange = Range(match.range(at: 2), in: text), let value = Int(text[valueRange]),
            let unitRange = Range(match.range(at: 3), in: text),
            let unit = Self.unit(text[unitRange].lowercased())
        else { return nil }
        self.value = value
        self.unit = unit
        self.prefix = Range(match.range(at: 1), in: text).map { text[$0].capitalized }
    }

    private static func unit(_ token: String) -> Unit? {
        switch token {
        case "s", "sec", "secs", "second", "seconds": .second
        case "m", "min", "mins", "minute", "minutes": .minute
        case "h", "hr", "hrs", "hour", "hours": .hour
        case "d", "day", "days": .day
        case "w", "wk", "wks", "week", "weeks": .week
        case "mo", "mos", "month", "months": .month
        case "y", "yr", "yrs", "year", "years": .year
        default: nil
        }
    }

    /// The long form, as other cards show it: "9 hours ago", "Streamed 1 day ago".
    public var text: String {
        let age = "\(value) \(unit.rawValue)\(value == 1 ? "" : "s") ago"
        return prefix.map { "\($0) \(age)" } ?? age
    }

    public func date(before now: Date = Date()) -> Date {
        now.addingTimeInterval(-Double(value) * unit.seconds)
    }
}

// MARK: - Counts

/// "1,585,288 views" → 1585288, "1.5K" → 1500, "529K views" → 529000, "2M" → 2000000.
public func parseCount(_ text: String) -> Int? {
    let pattern = #"([\d,]+(?:\.\d+)?)\s*([KkMmBb])\b"#
    if let regex = try? NSRegularExpression(pattern: pattern),
        let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let numRange = Range(match.range(at: 1), in: text),
        let suffixRange = Range(match.range(at: 2), in: text),
        let value = Double(text[numRange].replacingOccurrences(of: ",", with: ""))
    {
        let multiplier: Double =
            switch text[suffixRange].uppercased() {
            case "K": 1_000
            case "M": 1_000_000
            case "B": 1_000_000_000
            default: 1
            }
        return Int(value * multiplier)
    }
    let digits = text.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    return digits.isEmpty ? nil : Int(digits)
}

// MARK: - LockupMetadata

/// What a `lockupViewModel`'s metadata rows say, read by what each part *is* rather than
/// where it sits. YouTube varies the layout by surface:
///   - feeds, Up Next:       [channel] [views, age]         ("1M", "9h ago" when compact)
///   - search official card: [channel, views, age]          (one row)
///   - channel page:         [views, age]                   (no channel row)
public struct LockupMetadata: Equatable, Sendable {
    public var channelTitle: String?
    public var viewCount: Int?
    public var age: RelativeAge?
    public var isLive = false

    public init(rows: [[String]]) {
        for (rowIndex, row) in rows.enumerated() {
            for part in row {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                if age == nil, let parsed = RelativeAge(trimmed) {
                    age = parsed
                } else if viewCount == nil, Self.isViewCount(trimmed) {
                    viewCount = parseCount(trimmed) ?? 0  // "No views"
                    if trimmed.localizedCaseInsensitiveContains("watching") { isLive = true }
                } else if rowIndex == 0, channelTitle == nil, !trimmed.isEmpty {
                    // The channel is always on the first row when present.
                    channelTitle = trimmed
                }
            }
        }
    }

    /// "529K views", "1,234 views", "No views", "4.1K watching", or a bare compact count ("1M").
    static func isViewCount(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("view") || lower.contains("watching")
            || text.range(of: #"^\d[\d,.]*\s*[KkMmBb]?$"#, options: .regularExpression) != nil
    }
}
