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
    public func statePayload() async -> [String: Any] {
        let open = await reminders(includeCompleted: false)
        let byList = Dictionary(grouping: open, by: \.list)
        let lists: [[String: Any]] = self.lists().map { name in
            ["list": name,
             "items": (byList[name] ?? []).map { ["uid": $0.id, "summary": $0.title] }]
        }
        return ["lists": lists]
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
