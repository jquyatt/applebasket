import Foundation

/// One inbound write from Home Assistant (a user acted on a todo entity).
public struct HACommand: Decodable {
    public let op: String        // add | complete | delete
    public let list: String?
    public let summary: String?
    public let uid: String?
}

/// Pure client of HA's WebSocket API — no server on the Mac side.
/// Connects, authenticates, subscribes to `applebasket_command`, and reconnects
/// on drop. `URLSessionWebSocketTask` is stdlib; no dependency.
public final class HAWebSocket {
    private let url: URL
    private let token: String

    public init(_ config: HAConfig) {
        var c = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false)!
        c.scheme = (c.scheme == "https") ? "wss" : "ws"
        c.path = "/api/websocket"
        self.url = c.url!
        self.token = config.token
    }

    /// Runs until the task is cancelled. `onCommand` fires per inbound command;
    /// `onLink(up)` reports connection health for the popover's stale/ok state.
    public func run(onCommand: @escaping (HACommand) -> Void,
                    onLink: @escaping (Bool) -> Void) async {
        while !Task.isCancelled {
            do {
                try await session(onCommand: onCommand, onLink: onLink)
            } catch {
                onLink(false)
            }
            // ponytail: fixed 3s reconnect; switch to exponential backoff only if HA flaps.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    private func session(onCommand: @escaping (HACommand) -> Void,
                         onLink: @escaping (Bool) -> Void) async throws {
        let ws = URLSession.shared.webSocketTask(with: url)
        ws.resume()
        defer { ws.cancel(with: .goingAway, reason: nil) }

        // HA handshake: server says auth_required, we send the token, server replies auth_ok.
        _ = try await recv(ws)
        try await send(ws, ["type": "auth", "access_token": token])
        guard try await recv(ws)["type"] as? String == "auth_ok" else {
            throw URLError(.userAuthenticationRequired)
        }

        // Message ids are per-connection; each fresh session starts at 1.
        try await send(ws, ["id": 1, "type": "subscribe_events", "event_type": "applebasket_command"])
        onLink(true)

        while !Task.isCancelled {
            let msg = try await recv(ws)
            guard msg["type"] as? String == "event",
                  let data = (msg["event"] as? [String: Any])?["data"] as? [String: Any],
                  let raw = try? JSONSerialization.data(withJSONObject: data),
                  let cmd = try? JSONDecoder().decode(HACommand.self, from: raw)
            else { continue }
            onCommand(cmd)
        }
    }

    private func send(_ ws: URLSessionWebSocketTask, _ obj: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: obj)
        try await ws.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func recv(_ ws: URLSessionWebSocketTask) async throws -> [String: Any] {
        let bytes: Data
        switch try await ws.receive() {
        case .string(let s): bytes = Data(s.utf8)
        case .data(let d):   bytes = d
        @unknown default:    return [:]
        }
        return (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] ?? [:]
    }
}
