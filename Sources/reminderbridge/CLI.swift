import Foundation
import AppKit
import BridgeCore

// Test harnesses (Phase 5)
final class AccessibilityWalkerTest {
    func test(listName: String = "Inbox") async {
        print("🔍 Starting Accessibility walk test for '\(listName)'...")
        let walker = AccessibilityWalker()
        do {
            let items = try await walker.walk(listName: listName)
            print("✅ Accessibility walk succeeded")
            print("   Items found: \(items.count)")
            if items.isEmpty {
                print("   ⚠️  No items detected. Check that the list has items and is visible.")
            } else {
                for item in items {
                    print("")
                    print("   📋 \(item.title)")
                    if !item.tags.isEmpty {
                        print("      Tags: \(item.tags.joined(separator: ", "))")
                    }
                    if let section = item.section {
                        print("      Section: \(section)")
                    }
                    if let parent = item.parentTitle {
                        print("      Parent: \(parent)")
                    }
                }
            }
            print("")
            print("📸 Taking screenshot for verification...")
            try takeScreenshot(listName: listName)
        } catch AXWalkerError.noRemindersProcess {
            print("❌ Reminders app not running. Launch it and try again.")
        } catch AXWalkerError.accessibilityDenied {
            print("❌ Accessibility not granted to Reminders.")
            print("   System Settings → Privacy & Security → Accessibility")
            print("   Add com.apple.reminders to the list and try again.")
        } catch {
            print("❌ Walk failed with error: \(error)")
            print("   Type: \(type(of: error))")
        }
    }

    private func takeScreenshot(listName: String) throws {
        guard let remindersApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.reminders"
        ).first else {
            print("⚠️  Could not find Reminders app for screenshot")
            return
        }
        remindersApp.activate(options: .activateAllWindows)
        usleep(500_000)
        guard let screen = NSScreen.main else {
            print("⚠️  Could not get main screen for screenshot")
            return
        }
        guard let cgImage = CGWindowListCreateImage(
            screen.frame,
            .optionOnScreenBelowWindow,
            .zero,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            print("⚠️  Could not capture window")
            return
        }
        let nsImage = NSImage(cgImage: cgImage, size: screen.frame.size)
        let desktopPath = "~/Desktop/reminders-phase5-test.png"
            .replacingOccurrences(of: "~", with: NSHomeDirectory())
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:])
        else {
            print("⚠️  Could not encode screenshot")
            return
        }
        try pngData.write(to: URL(fileURLWithPath: desktopPath))
        print("✅ Screenshot saved to \(desktopPath)")
        print("   Compare it with the parsed items above.")
    }
}


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

            case "test-accessibility":
                let listName = positional(args, after: "test-accessibility") ?? "Inbox"
                let test = AccessibilityWalkerTest()
                await test.test(listName: listName)

            case "test-merge":
                let test = TitleMergeTest()
                test.runAll()

            case "test-payload":
                let payload = await store.statePayload()
                CLI.printJSON(payload)

            default:
                print("""
                reminderbridge — EventKit CLI (v0.1)
                  lists                                       list reminder-list names
                  list [--list NAME] [--all]                  print reminders as JSON
                  add <title> [--list NAME] [--notes TEXT]    create a reminder
                  done <id>                                   mark complete
                  remove <id>                                 delete
                  push                                        fire test event to HA
                  test-accessibility [LIST]                  test Phase 5 AX walk
                  test-merge                                 test Phase 5 title fuzzy-match
                  test-payload [LIST]                        show enriched state payload (Phase 5)
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
