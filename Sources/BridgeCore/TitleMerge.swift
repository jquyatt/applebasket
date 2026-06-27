import Foundation

// ponytail: Simple fuzzy title matching for merging AX items back to EventKit reminders.
// EventKit titles are ground truth (stable identifiers); AX titles may differ by whitespace/punctuation.

public final class TitleMerge {

    /// Find the best AX item match for an EventKit reminder title and REMOVE it
    /// from `axItems` so a second reminder with the same title can't re-claim it.
    /// `axItems` is in walk order; on a title tie we take the first remaining match,
    /// which keeps Morning's "Brush Teeth" and Night's "Brush Teeth" attributed in
    /// the order EventKit hands them to us.
    /// ponytail: EventKit can't expose section/parent, so we can't key the merge
    /// on them — title + consume-in-order is the only disambiguation available.
    public static func findBest(for eventKitTitle: String, in axItems: inout [AccessibilityItem]) -> AccessibilityItem? {
        let normalized = normalize(eventKitTitle)

        var bestIndex: Int?
        var bestDistance = Int.max

        for (i, axItem) in axItems.enumerated() {
            let distance = levenshteinDistance(normalized, normalize(axItem.title))
            guard distance <= 2 else { continue }   // exact or near-exact only
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = i
                if distance == 0 { break }          // exact wins immediately
            }
        }

        guard let idx = bestIndex else { return nil }
        return axItems.remove(at: idx)
    }

    /// Normalize a title for fuzzy comparison: trim, lowercase, remove punctuation.
    public static func normalize(_ title: String) -> String {
        return title
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .filter { !$0.isWhitespace || $0 == " " }  // collapse multiple spaces
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
    }

    /// Levenshtein distance between two strings (edit distance).
    /// Measures minimum edits (insert, delete, replace) to transform one to the other.
    public static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)

        // Empty input: distance is just the other length. Also avoids the
        // 1...0 range crash below when either string is empty.
        if s1.isEmpty { return s2.count }
        if s2.isEmpty { return s1.count }

        var dp = Array(repeating: Array(repeating: 0, count: s2.count + 1), count: s1.count + 1)

        for i in 0...s1.count {
            dp[i][0] = i
        }
        for j in 0...s2.count {
            dp[0][j] = j
        }

        for i in 1...s1.count {
            for j in 1...s2.count {
                let cost = s1[i - 1] == s2[j - 1] ? 0 : 1
                dp[i][j] = min(
                    dp[i - 1][j] + 1,      // delete
                    dp[i][j - 1] + 1,      // insert
                    dp[i - 1][j - 1] + cost  // replace
                )
            }
        }

        return dp[s1.count][s2.count]
    }
}
