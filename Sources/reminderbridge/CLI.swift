import Foundation
import BridgeCore

@main
struct CLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let store = EventKitStore()

        do {
            try await store.requestAccess()
        } catch {
            err("\(error)")
            exit(2)
        }

        let command = args.first ?? "help"
        do {
            switch command {
            case "lists":
                store.lists().forEach { print($0) }

            case "list":
                let items = await store.reminders(
                    in: value(for: "--list", in: args),
                    includeCompleted: args.contains("--all"))
                printJSON(items)

            case "add":
                guard let title = positional(args, after: "add") else {
                    usageExit("add <title> [--list NAME] [--notes TEXT]")
                }
                let dto = try store.add(
                    title: title,
                    to: value(for: "--list", in: args),
                    notes: value(for: "--notes", in: args))
                printJSON(dto)

            case "done":
                guard let id = positional(args, after: "done") else { usageExit("done <id>") }
                try store.setCompleted(id: id, true)

            case "remove":
                guard let id = positional(args, after: "remove") else { usageExit("remove <id>") }
                try store.remove(id: id)

            case "push":
                guard let cfg = HAConfig() else {
                    err("set APPLEBASKET_HA_URL and APPLEBASKET_HA_TOKEN"); exit(3)
                }
                let ok = await HAClient(cfg).fireEvent("applebasket_state", await store.statePayload())
                print(ok ? "ok" : "unreachable")
                if !ok { exit(1) }

            default:
                print("""
                reminderbridge — EventKit CLI (v0.1)
                  lists                                       list reminder-list names
                  list [--list NAME] [--all]                  print reminders as JSON
                  add <title> [--list NAME] [--notes TEXT]    create a reminder
                  done <id>                                   mark complete
                  remove <id>                                 delete
                  push                                        fire test event to HA
                """)
            }
        } catch {
            err("\(error)")
            exit(1)
        }
    }

    static func value(for flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func positional(_ args: [String], after command: String) -> String? {
        guard let idx = args.firstIndex(of: command) else { return nil }
        return args[(idx + 1)...].first { !$0.hasPrefix("--") }
    }

    static func printJSON<T: Encodable>(_ v: T) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(v), let s = String(data: data, encoding: .utf8) {
            print(s)
        }
    }

    static func err(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }

    static func usageExit(_ msg: String) -> Never {
        err("usage: reminderbridge \(msg)")
        exit(64)
    }
}
