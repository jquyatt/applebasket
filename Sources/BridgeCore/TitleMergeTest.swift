import Foundation

// Unit tests for TitleMerge fuzzy matching.
// Run via: swift test (if we add a test target) or inline in CLI.

public final class TitleMergeTest {

    public init() {}

    public func runAll() {
        testExactMatch()
        testFuzzyMatch()
        testDuplicateTitlesConsumeInOrder()
        testOneLiner()
        testNormalization()
        testLevenshtein()
        print("✅ All TitleMerge tests passed")
    }

    private func testExactMatch() {
        var ax = [
            AccessibilityItem(uid: "", title: "Email client", tags: ["urgent"], section: "Today", parentTitle: nil),
            AccessibilityItem(uid: "", title: "Fix bug", tags: [], section: nil, parentTitle: nil),
        ]

        let result = TitleMerge.findBest(for: "Email client", in: &ax)
        assert(result != nil, "Exact match should find item")
        assert(result?.tags.contains("urgent") == true, "Should preserve tags")
        assert(!ax.contains { $0.title == "Email client" }, "Should remove matched item")
    }

    private func testFuzzyMatch() {
        var ax = [
            AccessibilityItem(uid: "", title: " Email client ", tags: ["urgent"], section: nil, parentTitle: nil),
        ]

        let result = TitleMerge.findBest(for: "Email client", in: &ax)
        assert(result != nil, "Fuzzy match with leading/trailing space should find item")
        assert(ax.isEmpty, "Should remove matched item")
    }

    // The reason for the array API: two reminders share a title ("Brush Teeth"
    // in Morning and Night). Each findBest call must consume a distinct AX item,
    // preserving walk order, so sections don't get swapped or double-claimed.
    private func testDuplicateTitlesConsumeInOrder() {
        var ax = [
            AccessibilityItem(uid: "", title: "Brush Teeth", tags: [], section: "Morning", parentTitle: "Hygiene", walkIndex: 2),
            AccessibilityItem(uid: "", title: "Brush Teeth", tags: [], section: "Night", parentTitle: "Hygiene", walkIndex: 14),
        ]

        let first = TitleMerge.findBest(for: "Brush Teeth", in: &ax)
        let second = TitleMerge.findBest(for: "Brush Teeth", in: &ax)
        assert(first?.section == "Morning", "First match should be Morning (walk order)")
        assert(second?.section == "Night", "Second match should be Night")
        // The matched item carries the right walk position even for duplicate titles,
        // so the HA payload sorts Morning (2) before Night (14), not adjacent.
        assert(first?.walkIndex == 2, "Morning Brush Teeth keeps its walk position")
        assert(second?.walkIndex == 14, "Night Brush Teeth keeps its walk position")
        assert(ax.isEmpty, "Both duplicates consumed")
        assert(TitleMerge.findBest(for: "Brush Teeth", in: &ax) == nil, "No third match")
    }

    // The compact one-liner: [section] * [parent >] title [#tags]
    private func testOneLiner() {
        func item(_ section: String?, _ parent: String?, _ tags: [String]) -> AccessibilityItem {
            AccessibilityItem(uid: "", title: "x", tags: tags, section: section, parentTitle: parent)
        }
        // section + parent, no tags
        assert(EventKitStore.oneLiner(title: "Brush Teeth", ax: item("Morning", "Hygiene", []))
               == "Morning * Hygiene > Brush Teeth", "section+parent")
        // section + parent + tag
        assert(EventKitStore.oneLiner(title: "Lactic Acid", ax: item("Night", "Face/Neck", ["skincare"]))
               == "Night * Face/Neck > Lactic Acid #skincare", "section+parent+tag")
        // section only (a parent row, e.g. Hygiene itself) with tag
        assert(EventKitStore.oneLiner(title: "Hygiene", ax: item("Morning", nil, ["routine"]))
               == "Morning * Hygiene #routine", "section+tag, no parent")
        // no AX data at all → bare title
        assert(EventKitStore.oneLiner(title: "Loose Item", ax: nil)
               == "Loose Item", "nil ax → title only")
    }

    private func testNormalization() {
        let cases = [
            ("Email Client", "email client"),
            (" email  client ", "email client"),
            ("HELLO", "hello"),
        ]

        for (input, expected) in cases {
            let norm = TitleMerge.normalize(input)
            assert(norm == expected, "Normalize '\(input)' should be '\(expected)', got '\(norm)'")
        }
    }

    private func testLevenshtein() {
        let cases = [
            ("cat", "cat", 0),
            ("cat", "bat", 1),
            ("kitten", "sitting", 3),
            ("", "abc", 3),
            ("abc", "", 3),
        ]

        for (s1, s2, expected) in cases {
            let dist = TitleMerge.levenshteinDistance(s1, s2)
            assert(dist == expected, "Distance('\(s1)', '\(s2)') should be \(expected), got \(dist)")
        }
    }

    private func assert(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        print("❌ Test failed: \(message)")
        exit(1)
    }
}
