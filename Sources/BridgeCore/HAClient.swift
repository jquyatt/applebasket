import Foundation

// Gated stderr logging, same convention as the walker's dbg().
private func haDbg(_ s: String) {
    guard ProcessInfo.processInfo.environment["APPLEBASKET_DEBUG"] != nil else { return }
    FileHandle.standardError.write(Data(("HA: " + s + "\n").utf8))
}

/// Config from env. Set both or HA push is simply skipped (local-only mode).
/// NOTE: a GUI login item does NOT inherit your shell env. For the .app, seed
/// the session once:  launchctl setenv APPLEBASKET_HA_URL http://homeassistant.local:8123
/// ponytail: env var now; a config file lands when distribution needs one.
public struct HAConfig {
    public let baseURL: URL
    public let token: String

    public init?() {
        let env = ProcessInfo.processInfo.environment
        guard let urlStr = env["APPLEBASKET_HA_URL"], let url = URL(string: urlStr),
              let token = env["APPLEBASKET_HA_TOKEN"], !token.isEmpty
        else { return nil }
        self.baseURL = url
        self.token = token
    }
}

public final class HAClient {
    private let config: HAConfig
    public init(_ config: HAConfig) { self.config = config }

    /// Fire a generic HA event; the applebasket todo integration subscribes to it.
    /// ponytail: one full-snapshot event per change, not per-item add/complete/delete —
    /// HA reconciles the snapshot idempotently, so per-item deltas are unneeded.
    /// Returns true on HTTP 200 — that success/fail IS the reachability signal.
    @discardableResult
    public func fireEvent<T: Encodable>(_ event: String, _ payload: T) async -> Bool {
        let url = config.baseURL.appendingPathComponent("api/events/\(event)")
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(payload)

        // ponytail: collapse-to-false hid WHY pushes failed for a whole session.
        // Surface the real reason on stderr (gated) so unreachable is diagnosable.
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            if code != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                haDbg("HA POST \(url.absoluteString) → HTTP \(code) \(body.prefix(200))")
            }
            return code == 200
        } catch {
            haDbg("HA POST \(url.absoluteString) → \(error.localizedDescription)")
            return false
        }
    }
}
