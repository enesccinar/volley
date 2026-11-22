import Foundation

/// Typo-tolerant search for notifications and conversations: every query token must appear, in order but not
/// necessarily contiguously, in one of the item's fields. Tighter and word-start matches rank higher.
enum FuzzySearch {
    private static let consecutiveBonus = 5
    private static let wordStartBonus = 8

    /// Score of `token` as a subsequence of `field`, or nil if it isn't one. Higher is better.
    static func score(_ token: String, in field: String) -> Int? {
        let q = normalize(token), f = normalize(field)
        guard let first = q.first, !f.isEmpty else { return q.isEmpty ? 0 : nil }
        // Try each place the first character occurs and keep the best greedy alignment from there.
        var best: Int?
        for start in f.indices where f[start] == first {
            if let s = align(q, in: f, from: start), s > (best ?? .min) { best = s }
        }
        return best
    }

    /// Items matching every whitespace-separated token, best first, then newest first. Blank query → `items`.
    static func search(_ query: String, in items: [StoredNotification]) -> [StoredNotification] {
        search(query, in: items, fields: { [$0.appName, $0.title, $0.text] }, date: \.postedAt)
    }

    /// Conversations matching by name, number, group members or last message, best first, then newest first.
    static func search(_ query: String, in items: [ConversationSummary]) -> [ConversationSummary] {
        search(query, in: items, fields: { [$0.title, $0.address, $0.name ?? ""] + $0.participants + [$0.lastBody] },
               date: \.lastDate)
    }

    private static func search<T>(_ query: String, in items: [T], fields: (T) -> [String],
                                  date: KeyPath<T, Date>) -> [T] {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return items }
        let scored: [(T, Int)] = items.compactMap { item in
            let values = fields(item)
            var total = 0
            for token in tokens {
                guard let best = values.compactMap({ score(token, in: $0) }).max() else { return nil }
                total += best
            }
            return (item, total)
        }
        return scored.sorted { a, b in a.1 != b.1 ? a.1 > b.1 : a.0[keyPath: date] > b.0[keyPath: date] }.map(\.0)
    }

    private static func align(_ q: [Character], in f: [Character], from start: Int) -> Int? {
        var total = 0
        var fi = start
        var previous: Int?
        for c in q {
            while fi < f.count, f[fi] != c { fi += 1 }
            guard fi < f.count else { return nil }
            total += 1
            if let p = previous, p == fi - 1 { total += consecutiveBonus }
            if fi == 0 || !(f[fi - 1].isLetter || f[fi - 1].isNumber) { total += wordStartBonus }
            previous = fi
            fi += 1
        }
        return total
    }

    private static func normalize(_ s: String) -> [Character] {
        Array(s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil))
    }
}
