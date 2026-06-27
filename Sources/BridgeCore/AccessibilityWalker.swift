import AppKit
import Foundation

// ponytail: This walks Reminders' AX tree to extract structure EventKit hides:
// tags (sidebar + inline), sections, sub-tasks (detected by parent chevron heuristic).
// Needs Reminders app frontmost with Accessibility granted, ~1-2 sec per pass.
// Ground truth via screenshot verification (caught incorrect list selection in testing).

public enum AXWalkerError: Error {
    case noRemindersProcess
    case accessibilityDenied
}

public struct AccessibilityItem {
    public var uid: String               // EventKit id, matched by title fuzzy-merge
    public var title: String             // reminder title as read from the AX tree
    public var tags: [String]            // extracted from sidebar or inline "#tag"
    public var section: String?          // "Morning", "Night", etc.
    public var parentTitle: String?      // if a sub-task, title of the parent
    public var walkIndex: Int            // position in visual (top-to-bottom) walk order

    public init(uid: String, title: String, tags: [String], section: String?, parentTitle: String?, walkIndex: Int = 0) {
        self.uid = uid
        self.title = title
        self.tags = tags
        self.section = section
        self.parentTitle = parentTitle
        self.walkIndex = walkIndex
    }
}

// ponytail: debug lines go to stderr so they never corrupt the JSON payload on
// stdout (jq chokes otherwise). Gate behind APPLEBASKET_DEBUG to silence entirely.
private func dbg(_ s: String) {
    guard ProcessInfo.processInfo.environment["APPLEBASKET_DEBUG"] != nil else { return }
    FileHandle.standardError.write(Data((s + "\n").utf8))
}

public final class AccessibilityWalker {
    public init() {}

    /// Walk the frontmost Reminders window's AX tree for the named list.
    /// Returns items keyed by title (since EventKit doesn't expose calendarItemIdentifier
    /// from the AX tree). Caller merges back by title fuzzy-match.
    /// Takes 1–2 seconds (includes sleep after list selection).
    public func walk(listName: String) async throws -> [AccessibilityItem] {
        guard let remindersApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.reminders"
        ).first else {
            throw AXWalkerError.noRemindersProcess
        }

        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) else {
            throw AXWalkerError.accessibilityDenied
        }

        let appElement = AXUIElementCreateApplication(remindersApp.processIdentifier)

        // Navigate: Reminders window → main split → sidebar/list pane → click the list → main content pane
        guard let window = try getMainWindow(appElement) else {
            dbg("DEBUG: No window found")
            return []
        }
        dbg("DEBUG: Found Reminders window")

        // Click the list name in the sidebar to ensure it's selected.
        try await selectList(listName, in: window)
        dbg("DEBUG: Selected list '\(listName)'")

        // The content list is the one AXOutline in the window whose rows have
        // checkboxes. The sidebar is also an AXOutline but its rows don't.
        // ponytail: targeted search beats hardcoding the nested-split path,
        // which differs between macOS versions and sidebar collapse states.
        guard let outline = findContentOutline(window) else {
            dbg("DEBUG: No content outline found")
            return []
        }
        dbg("DEBUG: Found content outline")
        return try walkItems(in: outline)
    }

    private func getMainWindow(_ app: AXUIElement) throws -> AXUIElement? {
        var windows: AnyObject?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
        guard let winList = windows as? [AXUIElement], let window = winList.first else { return nil }
        return window
    }


    private func selectList(_ name: String, in window: AXUIElement) async throws {
        // Find the sidebar (left pane in split view), locate the button matching name, click it.
        // The window structure is roughly: window → split view → [sidebar, content area].
        // Sidebar contains list buttons; clicking one populates the content area.

        // The sidebar is an AXOutline. Its list entries are AXRows; the list name
        // lives in a nested static-text/text-field, and the row's AXDescription
        // starts with the name (e.g. "Personal Care, 6 items"). Match on that and
        // press the row. ponytail: match by text, not by a direct-child button —
        // there is no direct-child button, which is why selection silently no-op'd.
        guard let row = findSidebarRow(named: name, in: window) else {
            throw AXWalkerError.noRemindersProcess  // List not found in sidebar
        }
        // Select via AXSelected — the safe, non-destructive path. Do NOT press the
        // row or its descendants: sidebar rows contain a hidden share button, and
        // pressing descendants pops the "Participants" share sheet (observed in
        // testing). Setting selection switches the content pane without side effects.
        AXUIElementSetAttributeValue(row, kAXSelectedAttribute as CFString, kCFBooleanTrue)

        try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 sec for content to refresh
    }

    // Find the sidebar AXRow whose title text matches `name`. Searches the whole
    // window subtree, so it doesn't depend on locating the sidebar container first.
    private func findSidebarRow(named name: String, in window: AXUIElement) -> AXUIElement? {
        for row in descendants(window) where (try? getRole(row)) == kAXRowRole {
            // A sidebar list row has no checkbox (those are content rows).
            if (try? hasCheckbox(row)) == true { continue }
            if rowTitle(row) == name { return row }
        }
        return nil
    }

    // The list name: AXDescription on the row/cell is "<name>, N items"; else the
    // first non-empty nested static-text / text-field value.
    private func rowTitle(_ row: AXUIElement) -> String {
        for d in [row] + descendants(row) {
            var desc: AnyObject?
            AXUIElementCopyAttributeValue(d, kAXDescriptionAttribute as CFString, &desc)
            if let s = desc as? String, let head = s.split(separator: ",").first, !head.isEmpty {
                return String(head)
            }
        }
        for d in descendants(row) {
            let r = (try? getRole(d)) ?? ""
            guard r == kAXStaticTextRole || r == kAXTextFieldRole else { continue }
            var v: AnyObject?
            AXUIElementCopyAttributeValue(d, kAXValueAttribute as CFString, &v)
            if let s = v as? String, !s.isEmpty { return s }
        }
        return ""
    }


    private func walkItems(in contentArea: AXUIElement) throws -> [AccessibilityItem] {
        var result: [AccessibilityItem] = []   // walk order preserved
        var currentSection: String?
        var lastItemWasParent = false
        var lastParentTitle: String?

        // Content area might be an AXOutline or AXScrollArea; get its children
        guard let rows = try getRows(in: contentArea) else {
            dbg("DEBUG: No rows found in contentArea")
            return []
        }

        dbg("DEBUG: Found \(rows.count) rows in contentArea")

        // If the first row is an AXOutline, drill into its children
        var itemRows = rows
        if rows.count == 1 {
            let role = try getRole(rows[0])
            if role == kAXOutlineRole {
                dbg("DEBUG: Found AXOutline, drilling into its children...")
                if let outlineChildren = try getRows(in: rows[0]) {
                    itemRows = outlineChildren
                    dbg("DEBUG: Outline has \(outlineChildren.count) children")
                }
            }
        }

        for row in itemRows {
            let role = try getRole(row)
            let text = try getText(row)
            let hasChev = try hasChevron(row)
            let hasCheck = try hasCheckbox(row)

            guard role == kAXRowRole else { continue }

            if hasCheck {
                // A reminder. Sub-tasks (no chevron) following a parent (chevron)
                // belong to that parent until the next parent or section break.
                // ponytail: flat sibling-heuristic mis-attributes a parent's
                // top-level *sibling* as its child. Holds while every checkbox row
                // after a parent really is its subtask (true for these routines).
                // Upgrade path: read AXLevel/indentation off the cell if siblings appear.
                let tags = try extractTags(from: row)
                // A parent (has chevron) belongs to no parent itself.
                let parent = (!hasChev && lastItemWasParent) ? lastParentTitle : nil
                result.append(AccessibilityItem(
                    uid: "",  // filled by caller on merge
                    title: text,
                    tags: tags,
                    section: currentSection,
                    parentTitle: parent,
                    walkIndex: result.count   // position in visual order
                ))

                if hasChev {            // this row is itself a parent
                    lastItemWasParent = true
                    lastParentTitle = text
                }
            } else if !text.isEmpty {
                // No checkbox + has text = section header ("Morning", "Night").
                currentSection = text
                lastItemWasParent = false
                lastParentTitle = nil
            }
        }

        return result
    }

    private func getRows(in container: AXUIElement) throws -> [AXUIElement]? {
        var rows: AnyObject?
        AXUIElementCopyAttributeValue(container, kAXChildrenAttribute as CFString, &rows)
        return rows as? [AXUIElement]
    }

    private func getRole(_ elem: AXUIElement) throws -> String {
        var role: AnyObject?
        AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &role)
        return role as? String ?? ""
    }

    // Find every AXOutline in the window, pick the one whose rows contain a
    // checkbox somewhere in their subtree. That's the reminder list, not the sidebar.
    private func findContentOutline(_ window: AXUIElement) -> AXUIElement? {
        let all = [window] + descendants(window)
        let outlines = all.filter { (try? getRole($0)) == kAXOutlineRole }
        dbg("DEBUG: Found \(outlines.count) outlines in window")
        for o in outlines {
            let rows = (try? getRows(in: o)) ?? nil ?? []
            let withCheck = rows.contains { (try? hasCheckbox($0)) == true }
            dbg("DEBUG:   outline rows=\(rows.count) hasCheckboxRow=\(withCheck)")
            if withCheck { return o }
        }
        // Fallback: the outline with the most rows (sidebar is usually shorter).
        return outlines.max { (try? getRows(in: $0))??.count ?? 0 < (try? getRows(in: $1))??.count ?? 0 }
    }

    // ponytail: Reminders nests row content (checkbox, text, chevron) inside an
    // AXCell/AXGroup under each AXRow, not as direct row children. Flatten the
    // subtree once so the existing direct-child checks just work.
    private func descendants(_ elem: AXUIElement) -> [AXUIElement] {
        var out: [AXUIElement] = []
        var kids: AnyObject?
        AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &kids)
        for child in (kids as? [AXUIElement] ?? []) {
            out.append(child)
            out.append(contentsOf: descendants(child))
        }
        return out
    }

    private func getText(_ elem: AXUIElement) throws -> String {
        // Title on the row itself first; otherwise pull from the nested static text.
        var text: AnyObject?
        AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &text)
        if let t = text as? String, !t.isEmpty { return t }
        AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &text)
        if let v = text as? String, !v.isEmpty { return v }

        // The reminder title is the AXTextField's value (not a static text —
        // static texts here are tags/links). Confirmed via AX probe.
        for d in descendants(elem) where (try? getRole(d)) == kAXTextFieldRole {
            var val: AnyObject?
            AXUIElementCopyAttributeValue(d, kAXValueAttribute as CFString, &val)
            if let s = val as? String, !s.isEmpty { return s }
        }
        return ""
    }

    private func hasRole(_ elem: AXUIElement, _ wanted: String) -> Bool {
        descendants(elem).contains { (try? getRole($0)) == wanted }
    }

    private func hasCheckbox(_ elem: AXUIElement) throws -> Bool {
        hasRole(elem, kAXCheckBoxRole)
    }

    // The subtask disclosure is an AXButton with description "Show/Hide subtasks",
    // not a disclosure triangle. Presence of it = this reminder is a parent.
    private func hasChevron(_ elem: AXUIElement) throws -> Bool {
        for d in descendants(elem) where (try? getRole(d)) == kAXButtonRole {
            var desc: AnyObject?
            AXUIElementCopyAttributeValue(d, kAXDescriptionAttribute as CFString, &desc)
            if let s = desc as? String, s.contains("subtask") { return true }
        }
        return false
    }

    private func extractTags(from row: AXUIElement) throws -> [String] {
        var tags: [String] = []
        for child in descendants(row) {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            guard (role as? String) == kAXStaticTextRole else { continue }

            var text: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &text)
            guard let str = text as? String, str.hasPrefix("#") else { continue }

            // Extract tag name (e.g., "#routine" → "routine")
            let tag = String(str.dropFirst())
            tags.append(tag)
        }

        return tags
    }
}
