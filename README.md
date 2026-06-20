# Apple Basket

EventKit ↔ Home Assistant bridge for a Mac that stays logged in.
Keep your Apples at Home 🧺

**This repo carries both halves of the bridge** — the macOS app and the Home
Assistant integration — which run on separate machines and talk over your LAN:

```
Sources/                         macOS menu bar app + `reminderbridge` CLI (Swift)
  BridgeCore/                    shared EventKit wrapper
  reminderbridge/                CLI -> binary `reminderbridge`
  ReminderBridgeApp/             menu bar app (MenuBarExtra)
app/                             .app bundle plist + build/sign script
custom_components/applebasket/   Home Assistant integration (install via HACS)
hacs.json                        makes the repo a HACS custom repository
```

The Mac side you build from source (`swift build`) and run as a login item; the
HA side installs into Home Assistant through HACS (or a manual copy). The two are
independent — HACS only pulls `custom_components/applebasket/` and ignores the
Swift app.

## Build

```sh
swift build -c release          # builds all three targets
```

Requires Xcode Command Line Tools. No third-party packages.

## Make the .app

A bare SwiftPM binary lacks an Info.plist, so `requestFullAccessToReminders()` fails. A signed `.app` bundle gets both the usage string and a stable code identity for TCC to pin the grant to.

**Signing.** Ad-hoc signatures change every rebuild, which re-prompts TCC each time. Create a self-signed code-signing cert in Keychain once — then approve the Reminders prompt once, and rebuilds keep the grant.

1. Keychain Access → Certificate Assistant → Create a Certificate
2. Name it `Apple Basket Dev`, Identity Type **Self Signed Root**, Certificate Type **Code Signing**
3. Build and sign:

```sh
./app/make_app.sh "Apple Basket Dev"
mv AppleBasket.app /Applications/
```

(For a smoke test, omit the identity: `./app/make_app.sh` will ad-hoc sign.)

## First run + permission

Launch `/Applications/AppleBasket.app` in GUI. Two approval prompts appear — click
**OK / Allow** on each:

1. **Reminders** — to read and write your lists.
2. **Local Network** — to reach Home Assistant on your LAN (macOS 15+). Without it,
   the bridge can't push to or hear from HA, and the menu bar dot stays yellow
   (`stale`). You can also toggle it later under System Settings → Privacy &
   Security → Local Network.

The menu bar checklist icon comes live. Click it to see status, open count, last change, and your bridged lists.

The grants live in the user TCC database. They survive reboots and OS updates within the same major version. If `tccutil reset Reminders com.jquyatt.applebasket` wipes the Reminders grant, just re-approve the prompt.

## Make it resident

System Settings → General → Login Items → **＋** → add AppleBasket.app.

Or register programmatically: call `SMAppService.mainApp.register()` from inside the app. Manual add is simpler for now.

A login item runs in the GUI session, which is what EventKit requires.

## CLI (scripting)

The CLI borrows the grant of its parent shell (e.g., Terminal). Useful for one-off commands or scripts.

```
reminderbridge lists
reminderbridge list [--list NAME] [--all]
reminderbridge add <title> [--list NAME] [--notes TEXT]
reminderbridge done <id>
reminderbridge remove <id>
reminderbridge push                  # fire an applebasket_state snapshot to HA
```

## Build gotcha (read this)

`./app/make_app.sh` only builds the **AppleBasket** app product. It does **not**
rebuild the **reminderbridge** CLI. After changing shared code in `BridgeCore`,
rebuild both or the CLI silently runs stale code:

```sh
swift build -c release            # builds ALL products (app + CLI)
```

To confirm a binary is current, check the event name compiled into it:

```sh
strings .build/release/reminderbridge | grep -E 'applebasket_(state|changed)'
# want: applebasket_state   (applebasket_changed = stale Phase 1 build)
```

A stale CLI fires the old event name, HA ignores it, `push` still prints `ok`,
and you chase ghosts for hours. Don't.

## Home Assistant integration

Each Reminders list becomes a native HA `todo.*` entity, bidirectional. The Mac is
a pure client of HA's WebSocket API — no server runs on the Mac. Outbound state
goes out as REST events (`applebasket_state`, a full open-items snapshot HA
reconciles idempotently); inbound writes (`add` / `complete` / `delete`) come back
over the WebSocket as `applebasket_command` events. There's no optimistic update —
the next snapshot (~1s) reflects the change, which sidesteps uid reconciliation.

**Install the integration** (on the HA box). Two routes:

*Via HACS (recommended).* HACS → ⋮ → **Custom repositories** → add
`https://github.com/jquyatt/applebasket`, category **Integration** → **Download**.
HACS handles future updates with a click — no manual file copying, no stale
bytecode to clear.

*Manual.* Copy the folder and restart HA:

```sh
cp -r custom_components/applebasket <config>/custom_components/
```

Either way, after restarting HA add it once in the UI: **Settings → Devices &
Services → ＋ Add Integration → Apple Basket**. It's a config-entry integration —
no `configuration.yaml` edit, single instance, no fields to fill in (the HA URL and
token live on the Mac side). The entry persists across restarts.

> Only relevant to **manual** installs: editing the integration's Python later
> means clearing its bytecode first — `rm -rf <config>/custom_components/applebasket/__pycache__`
> — or HA may keep running stale code (the cache is root-owned, so use an
> SSH/File-Editor add-on). HACS sidesteps this entirely.

**Wire the Mac.** Configure the HA connection (below), then rebuild and relaunch:

```sh
./app/make_app.sh "Apple Basket Dev"
rm -rf /Applications/AppleBasket.app && mv AppleBasket.app /Applications/
open /Applications/AppleBasket.app
```

## Configure the HA connection

Apple Basket reads two environment variables. Set both, or it runs local-only
(menu bar works, nothing is pushed to HA):

| variable | value |
|----------|-------|
| `APPLEBASKET_HA_URL` | your HA base URL, e.g. `http://homeassistant.local:8123` |
| `APPLEBASKET_HA_TOKEN` | a HA **long-lived access token** |

Create the token in HA: your profile (bottom-left avatar) → **Security** →
**Long-Lived Access Tokens** → **Create Token**. One token covers both the REST
push and the WebSocket.

**For the CLI**, export them in the shell you run `reminderbridge` from:

```sh
export APPLEBASKET_HA_URL=http://homeassistant.local:8123
export APPLEBASKET_HA_TOKEN=<your-token>
```

**For the menu bar app** — a login item, which does *not* inherit your shell env —
seed the GUI session instead:

```sh
launchctl setenv APPLEBASKET_HA_URL http://homeassistant.local:8123
launchctl setenv APPLEBASKET_HA_TOKEN <your-token>
```

`launchctl setenv` doesn't survive a reboot; make it permanent with a LaunchAgent
once you settle on a deployment. Keep the token out of the repo — it's a
credential, env-only by design.

## Phases

**Phase 0 — EventKit foundation** ✅
Menu bar app + CLI over one shared EventKit core, proving read / write / watch as a
resident login-item app on the auto-login desktop.

- [x] menu bar icon appears, shows your lists after approval
- [x] CLI `add` round-trips to iPhone/Mac, popover count updates
- [x] ticking a reminder on your phone updates "Last change" in the popover
- [x] TCC grant + login item survive a reboot

**Phase 1 — Transport** ✅
Resident watcher: every EventKit change pushes a full state snapshot to HA over the
REST events API (`applebasket_state`), and the menu bar reflects HA reachability —
green **Bridged** when the push lands, yellow **HA unreachable** when it doesn't.
Verified events landing on HA's bus and the status light tracking reachability live.

**Phase 2 — Home Assistant to-do entities** ✅
Each Reminders list is a native HA `todo.*` entity, bidirectional over REST +
WebSocket (setup under [Home Assistant integration](#home-assistant-integration)).

- [x] Reminders lists appear as `todo.*` entities, open items populated
- [x] `todo.add_item` in HA appears in Reminders within seconds
- [x] completing an item in HA ticks it in Reminders, and the reverse
- [x] HA restart → bridge goes `stale` → WebSocket reconnects and catches up

**Phase 3 — Calendar + Health** ⬜
Same app, surface Calendar and HealthKit as HA sensors.
# applebasket
