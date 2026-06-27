import EventKit
import Foundation

public enum BridgeError: Error, CustomStringConvertible {
    case accessDenied
    case listNotFound(String)
    case reminderNotFound(String)
    case noDefaultList

    public var description: String {
        switch self {
        case .accessDenied:
            return "Reminders access not granted. Approve in System Settings → Privacy & Security → Reminders."
        case .listNotFound(let n):
            return "No reminders list named \"\(n)\"."
        case .reminderNotFound(let id):
            return "No reminder with id \(id)."
        case .noDefaultList:
            return "No default reminders list configured in the Reminders app."
        }
    }
}

public struct ReminderDTO: Codable {
    public let id: String
    public let list: String
    public let title: String
    public let completed: Bool
    public let due: String?      // ISO8601
    public let notes: String?
}

/// applebasket_state event body. Codable so it encodes to JSON directly and ships
/// to HA. `summary` is the compact one-liner; section/parent/tags ship raw too for
/// custom cards. Optionals with nil are omitted by the encoder below.
public struct StatePayload: Codable {
    public struct Item: Codable {
        public let uid: String
        public let summary: String
        public let due: String?
        public let notes: String?
        public let section: String?
        public let parentTitle: String?
        public let tags: [String]?
    }
    public struct List: Codable {
        public let list: String
        public let items: [Item]
    }
    public let lists: [List]
}

public final class EventKitStore {
    public let store = EKEventStore()

    public init() {}

    public func requestAccess() async throws {
        let granted: Bool
        if #available(macOS 14.0, *) {
            granted = try await store.requestFullAccessToReminders()
        } else {
            granted = try await store.requestAccess(to: .reminder)
        }
        guard granted else { throw BridgeError.accessDenied }
    }

    public func lists() -> [String] {
        store.calendars(for: .reminder).map(\.title).sorted()
    }

    private func calendar(named name: String) throws -> EKCalendar {
        guard let cal = store.calendars(for: .reminder).first(where: { $0.title == name }) else {
            throw BridgeError.listNotFound(name)
        }
        return cal
    }

    public func reminders(in listName: String? = nil, includeCompleted: Bool = false) async -> [ReminderDTO] {
        let calendars: [EKCalendar]
        if let listName, let cal = try? calendar(named: listName) {
            calendars = [cal]
        } else {
            calendars = store.calendars(for: .reminder)
        }
        let predicate = store.predicateForReminders(in: calendars)
        let items: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { found in
                cont.resume(returning: found ?? [])
            }
        }
        return items
            .filter { includeCompleted || !$0.isCompleted }
            .map(ReminderDTO.init(from:))
    }

    @discardableResult
    public func add(title: String, to listName: String?, notes: String?) throws -> ReminderDTO {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        if let listName {
            reminder.calendar = try calendar(named: listName)
        } else if let def = store.defaultCalendarForNewReminders() {
            reminder.calendar = def
        } else {
            throw BridgeError.noDefaultList
        }
        reminder.notes = notes
        try store.save(reminder, commit: true)
        return ReminderDTO(from: reminder)
    }

    /// Body of an `applebasket_state` event: open items grouped by list, every
    /// list present (even empty). Snapshot-shaped so HA reconciles idempotently.
    /// If Accessibility is available, enriches items with tags, sections, sub-task structure.
    public func statePayload() async -> StatePayload {
        let open = await reminders(includeCompleted: false)
        let byList = Dictionary(grouping: open, by: \.list)
        let walker = AccessibilityWalker()

        var lists: [StatePayload.List] = []

        for name in self.lists() {
            // Fetch AX data for this list once, then merge into all items
            var axData = (try? await walker.walk(listName: name)) ?? []

            let ranked = (byList[name] ?? []).map { reminder -> (Int, StatePayload.Item) in
                // AX structure (Phase 5): tags, sections, sub-task parent.
                // ponytail: swallows AX errors (not granted / app not frontmost);
                // item then ships with EventKit data only, no degradation.
                let ax = TitleMerge.findBest(for: reminder.title, in: &axData)
                let item = StatePayload.Item(
                    uid: reminder.id,
                    summary: Self.oneLiner(title: reminder.title, ax: ax),
                    due: reminder.due,
                    notes: reminder.notes,
                    section: ax?.section,
                    parentTitle: ax?.parentTitle,
                    tags: (ax?.tags.isEmpty == false) ? ax?.tags : nil
                )
                // Sort key = the matched item's visual walk position. The matched
                // item is the correct one even for duplicate titles (findBest consumes
                // in order), so collisions sort right. No AX match → last.
                return (ax?.walkIndex ?? Int.max, item)
            }
            // Stable sort by walk position; unmatched (Int.max) keep EventKit order, last.
            let items = ranked.enumerated()
                .sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }
                .map { $0.element.1 }
            lists.append(StatePayload.List(list: name, items: items))
        }

        return StatePayload(lists: lists)
    }

    /// Compact display line: `[section] * [parent >] title [#tags]`
    /// e.g. "Morning * Hygiene > Brush Teeth", "Night * Face/Neck > Lactic Acid #skincare"
    static func oneLiner(title: String, ax: AccessibilityItem?) -> String {
        guard let ax else { return title }

        // Right side: "parent > title #tags"
        var right = title
        if let parent = ax.parentTitle {
            right = "\(parent) > \(right)"
        }
        if !ax.tags.isEmpty {
            right += " " + ax.tags.map { "#\($0)" }.joined(separator: " ")
        }

        // Section prefix joined with " * " per the payload spec.
        if let section = ax.section {
            return "\(section) * \(right)"
        }
        return right
    }

    private func reminder(id: String) throws -> EKReminder {
        guard let item = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw BridgeError.reminderNotFound(id)
        }
        return item
    }

    public func setCompleted(id: String, _ completed: Bool) throws {
        let r = try reminder(id: id)
        r.isCompleted = completed
        try store.save(r, commit: true)
    }

    public func remove(id: String) throws {
        try store.remove(try reminder(id: id), commit: true)
    }

    /// Fires on ANY EventKit change (calendars included). Filter downstream.
    public func onChange(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main) { _ in handler() }
    }
}

private extension ReminderDTO {
    init(from r: EKReminder) {
        let iso = ISO8601DateFormatter()
        let dueDate = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        self.init(
            id: r.calendarItemIdentifier,
            list: r.calendar?.title ?? "",
            title: r.title ?? "",
            completed: r.isCompleted,
            due: dueDate.map { iso.string(from: $0) },
            notes: r.notes
        )
    }
}
