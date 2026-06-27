import SwiftUI

struct PopoverView: View {
    @ObservedObject var model: BridgeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.status.color)
                    .frame(width: 9, height: 9)
                Text(model.status.label)
                    .font(.headline)
                Spacer()
            }

            Divider()

            switch model.status {
            case .ok, .stale:
                if case .stale = model.status {
                    Text("Home Assistant unreachable — retrying on next change")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("\(model.openCount) open · \(model.lists.count) lists")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let last = model.lastChange {
                    Text("Last change \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No changes seen yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !model.lists.isEmpty {
                    Divider()
                    ForEach(model.lists, id: \.self) { name in
                        Label(name, systemImage: "list.bullet")
                            .font(.caption)
                    }
                }

            case .localOnly:
                Text("Reading Reminders locally, but not connected to Home Assistant.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Set APPLEBASKET_HA_URL and APPLEBASKET_HA_TOKEN (via launchctl setenv for the app), then relaunch.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.lists.isEmpty {
                    Divider()
                    ForEach(model.lists, id: \.self) { name in
                        Label(name, systemImage: "list.bullet")
                            .font(.caption)
                    }
                }

            case .noAccess:
                Text("Approve Reminders in System Settings → Privacy & Security → Reminders, then reopen the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

            case .starting:
                Text("Connecting to EventKit…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Refresh") {
                    Task { await model.refresh(markChange: false) }
                }
                Spacer()
                Button("Quit") { model.quit() }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(12)
        .frame(width: 260)
    }
}
