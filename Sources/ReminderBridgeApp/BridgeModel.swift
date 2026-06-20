import Foundation
import SwiftUI
import AppKit
import BridgeCore

@MainActor
final class BridgeModel: ObservableObject {

    enum Status {
        case starting
        case ok
        case stale          // bridged locally, HA unreachable
        case noAccess

        var symbol: String {
            switch self {
            case .starting: return "ellipsis.circle"
            case .ok:       return "checklist"
            case .stale:    return "checklist.unchecked"
            case .noAccess: return "lock.slash"
            }
        }
        var label: String {
            switch self {
            case .starting: return "Starting…"
            case .ok:       return "Bridged"
            case .stale:    return "HA unreachable"
            case .noAccess: return "No Reminders access"
            }
        }
        var color: Color {
            switch self {
            case .starting: return .secondary
            case .ok:       return .green
            case .stale:    return .yellow
            case .noAccess: return .orange
            }
        }
    }

    @Published var status: Status = .starting
    @Published var lastChange: Date?
    @Published var lists: [String] = []
    @Published var openCount: Int = 0

    private let store = EventKitStore()
    private let config = HAConfig()                       // nil => local-only mode
    private lazy var haClient = config.map(HAClient.init)
    private var observer: NSObjectProtocol?
    private var wsTask: Task<Void, Never>?

    // Two inputs to the status light: did the last push land, is the WS up.
    private var pushOK = true
    private var linkUp = false

    init() {
        Task { await start() }
    }

    func start() async {
        do {
            try await store.requestAccess()
        } catch {
            status = .noAccess
            return
        }
        observer = store.onChange { [weak self] in
            Task { await self?.refresh(markChange: true) }
        }
        if let config {
            let ws = HAWebSocket(config)
            wsTask = Task { [weak self] in
                await ws.run(
                    onCommand: { cmd in Task { await self?.apply(cmd) } },
                    onLink:    { up  in Task { @MainActor in self?.linkUp = up; self?.recomputeStatus() } })
            }
        }
        await refresh(markChange: false)
    }

    func refresh(markChange: Bool) async {
        let items = await store.reminders(includeCompleted: false)
        lists = store.lists()
        openCount = items.count
        if markChange { lastChange = Date() }

        if let haClient {
            pushOK = await haClient.fireEvent("applebasket_state", await store.statePayload())
        }
        recomputeStatus()
    }

    /// Apply an inbound HA command to Reminders. Best-effort: the EventKit change
    /// observer fires afterward and pushes a fresh snapshot, which reconciles HA.
    func apply(_ cmd: HACommand) async {
        do {
            switch cmd.op {
            case "add":
                if let summary = cmd.summary { try store.add(title: summary, to: cmd.list, notes: nil) }
            case "complete":
                if let uid = cmd.uid { try store.setCompleted(id: uid, true) }
            case "delete":
                if let uid = cmd.uid { try store.remove(id: uid) }
            default:
                break
            }
        } catch {
            // ponytail: swallow; HA re-syncs from the next state snapshot anyway.
        }
    }

    private func recomputeStatus() {
        guard config != nil else { status = .ok; return }   // local-only: always OK
        status = (pushOK && linkUp) ? .ok : .stale
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
