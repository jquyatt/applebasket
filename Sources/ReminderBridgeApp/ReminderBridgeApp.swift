import SwiftUI

@main
struct ReminderBridgeApp: App {
    @StateObject private var model = BridgeModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            // Menu-bar glyph changes shape with state. The menu bar renders this
            // as a template (monochrome) image, so shape — not color — is the
            // reliable signal here; the colored dot lives in the popover.
            Image(systemName: model.status.symbol)
        }
        .menuBarExtraStyle(.window)
    }
}
