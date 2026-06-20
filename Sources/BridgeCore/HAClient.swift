import Foundation

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
    public func fireEvent(_ event: String, _ payload: [String: Any]) async -> Bool {
        var req = URLRequest(url: config.baseURL.appendingPathComponent("api/events/\(event)"),
                             timeoutInterval: 5)
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return true
    }
}
