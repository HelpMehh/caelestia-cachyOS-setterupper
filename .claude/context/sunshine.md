# Sunshine (game streaming)

## Design

- `capture = wlr`. `global_prep_cmd` runs `bin/sunshine-vd-start` and
  `bin/sunshine-vd-stop`. Start creates a headless `sunshine_vd` output sized
  to the client and turns the real monitors off. Stop restores them.
- The monitor layout is saved in a state file that `hypr/base.lua` re-applies
  on reload.
- **Monitors black after a stream (fix in v21, waiting on a real test):**
  - Symptom: after a stream was quit, every real monitor stayed black and
    only a TTY worked. It kept happening when a stream was left running for
    hours and reconnected to from a phone a few times, or when the client was
    closed before it confirmed the quit. Programs kept running.
  - Cause (worked out from the code, not seen in a log): start overwrote
    `sunshine_vd.outputs` with the monitors `hyprctl monitors -j` listed. If
    start ran again before a stop, the real monitors were already off and
    unlisted, so the list came out empty and stop had nothing to switch back
    on. It wasn't confirmed whether Sunshine re-runs `do` when a client
    resumes, or whether a stop was skipped. A web search found nothing on
    resume behaviour.
  - Fix: start merges the saved list with the monitors that are on. Stop
    checks whether any real monitor is on after re-enabling, and if none is,
    runs `hyprctl reload`. The state file is already gone by then, so the
    reload restores the normal layout, and monitors the layout disables on
    purpose stay off.
  - Logging: both scripts write to Sunshine's journal. Each start writes
    `sunshine-vd-start: turning off <names>`, and a fallback writes
    `sunshine-vd-stop: no monitor came back, reloading Hyprland's config`.
    Read them with
    `journalctl --user -u <sunshine unit> --since today | grep sunshine-vd`.
  - Planned test: use it as before (stream left running while away,
    reconnecting from a phone, quit at the end), then check the monitors
    come back. In the journal, see whether start ran more than once per quit,
    which answers the resume question, and whether the fallback fired. If
    every start lists all monitors and no fallback fired, the merge did the
    work. If the monitors still stay black, the cause is something else.
    Note what the journal shows and whether the PC was locked or the screens
    were off at the time.
  - Still open: if Sunshine crashes or is restarted mid-stream, `undo` never
    runs, and the monitors stay off until a later stream ends. A systemd
    drop-in with `ExecStopPost=` running `sunshine-vd-stop` would cover it.
    Only worth doing if it's ever seen.
  - Recovery from a TTY is in the README ("If something goes wrong").
- Sunshine starts after the shell, because it quits when there's no tray.

## Firewall (ufw)

- TCP 47984, 47989, 48010 and UDP 47998–48000, 48002, 48010 (Sunshine's
  standard ports).
- Allowed from the local network by default. When "Stream from outside your
  home network?" is answered yes (v15), they're open to everyone, UPnP replies
  are allowed (UDP **from** port 1900) and `upnp = enabled` is set. UPnP
  doesn't work without that port-1900 rule.

## Pairing and remote connections

How Moonlight-style clients (Moonlight, Artemis) talk to Sunshine:

1. `serverinfo` over HTTP **47989**. The PC shows up (locked).
2. `pair?…getservercert` over HTTP 47989. This request stays open until the
   PIN is entered in the web UI (`https://localhost:47990`).
3. The rest of the challenge exchange, still over HTTP 47989.
4. `pairchallenge` over HTTPS **47984**. This is the first use of 47984.
5. After that, the app list and launching use HTTPS 47984. Streaming also
   uses UDP 47998–48000 and 48002, plus TCP 48010.

So "PC visible but locked" only proves 47989 works.

**Hung HTTPS port (seen once, 2026-10, Sunshine `2026.1008`):** Sunshine's
HTTPS server on 47984 stopped serving about a minute after start, during a
pairing attempt from outside. 47989 kept working, so the PC showed up locked.
The PIN seemed to be accepted, then the client failed with "read error". It
affected LAN clients too. A port forward or UPnP problem looks the same from
the client, so check this first:

- `ss -tln | grep 47984`: a **Recv-Q above 0 that stays there** means
  Sunshine has stopped accepting connections. Many CLOSE-WAIT sockets on
  47984 with unread bytes (`ss -tn`) confirm it.
- Fix: `systemctl --user restart <sunshine unit>`. The unit name comes from
  `sunshine_unit`.
- Cause unknown. Start-up and config were normal, UPnP mappings completed,
  and settings all live in `~/.config/sunshine`. A home-folder restore after
  a drive wipe was suspected but not supported by anything. If it happens
  again, read the journal for the minutes *after* start-up, where the hang
  began, and note what the client was doing.
- A client can't reach the PC over IPv6 if the PC has only a link-local IPv6
  address.

## Lessons from earlier setups

- **Bar blurred / screen edges dead after a stream:** a race in the shell's
  monitor lookup. Fixed by the "reactive monitor lookup" patch, a
  `reloadShell` IPC command, and a workspace-offset reset in
  `sunshine-vd-stop`.
- **Apps not playing into Sunshine's sink:** led to the design where the lock
  video's audio follows the default output.

## Idle, lock and suspend

- **Remote streams dropping were caused by Caelestia suspending the PC.**
  logind logs `suspend requested from client … ('qs')`. It happened even
  mid-stream with "Keep awake" switched on.
- **Caelestia's defaults** (`plugin/src/Caelestia/Config/generalconfig.hpp` in
  its source): `general.idle.timeouts` = lock at 180 s, `dpms off` / `dpms on`
  at 300 s, `["suspendThenHibernate"]` at 600 s. `lockBeforeSleep` true,
  `inhibitWhenAudio` true, each timeout's `respectInhibitors` true. A
  `shell.json` without an idle section gets these defaults.
- **Why "Keep awake" fails during streams** (best explanation, not proven):
  `services/IdleInhibitor.qml` attaches a Wayland idle inhibitor to an
  invisible 0×0 `PanelWindow`. Hyprland only honours inhibitors on visible
  surfaces, and `sunshine-vd-start` turns the real monitors off.
- **Manual workaround:** a `general.idle.timeouts` list in `shell.json`
  without the suspend entry.
- **Sleep is blocked during streams (v18):** `sunshine-vd-start` runs
  `systemd-inhibit --what=sleep --mode=block … sleep infinity` in the
  background and saves its PID in `$XDG_RUNTIME_DIR/sunshine_vd.inhibit`;
  `sunshine-vd-stop` kills it first thing. It stays in Sunshine's cgroup, so
  a Sunshine crash or restart ends it too. The PID is only killed when
  `/proc/<pid>/comm` is `systemd-inhibit`. Input through a stream already
  counts as activity (tested: no lock or screen-off over 6 minutes), so only
  suspend needed handling.
- **polkit:** `inhibit-block-sleep` is `yes` for active/inactive sessions but
  `auth_admin_keep` for "any". A process outside a login session (tested: a
  user with no session) is refused. Sunshine runs as a user service, but
  polkit maps it to the user's graphical session, so the block is allowed
  (tested on a real desktop, v18). If it's ever refused, the stream still
  starts and Sunshine's log shows `sunshine-vd-start: could not block sleep`.
- **Test results (v18):** the block shows in `systemd-inhibit --list` during
  a stream and is gone after it. With the suspend timeout set to 60 s and no
  input, the stream stayed up.
- Caelestia's power menu has no plain suspend button. Its buttons are log
  out, shut down, hibernate and reboot. On a PC without hibernation set up,
  "hibernate" only shows "Hibernation has not been enabled".
- **No idle sleep between streams (v18, `step_idle_sleep`):** runs at install
  and update when Sunshine and "stream from outside" are both yes. It sets
  `inhibitWhenCharging: true` on each sleep entry in
  `general.idle.timeouts` of `$CFG/shell.json`, only where the key is missing
  (a user's `false` stays). Without a timeouts list it writes Caelestia's
  defaults with the key added. That pins those defaults on the machine if
  Caelestia changes them later. A "no" never undoes it. `check` shows a NOTE
  when remote is on and a sleep entry would still fire on mains power.
  - Why this and not an "Allow sleep when idle?" question: `shell.json` is in
    the private config repo, so it's shared by all of a user's computers. A
    "no" on the desktop would also stop the laptop sleeping on battery. The
    shell reads `inhibitWhenCharging` as "not while `!UPower.onBattery`", so
    one shared file gives per-machine behaviour. A desktop is never on
    battery, and without UPower `onBattery` is false too, so the entry is
    skipped.
  - Use the **per-entry** key. `general.idle.inhibitWhenCharging` also exists
    and would pause *every* timer, lock and screen-off included.
  - Sleep entries are recognised the way `SessionManager.exec` reads an
    action: an optional `systemctl`/`loginctl` in front, `-`/`_` ignored, any
    case (`suspend`, `suspendThenHibernate`, `hibernate`). A string action goes
    to Hyprland's dispatcher instead, so `exec systemctl suspend` is caught by
    scanning every word.
  - Key names and defaults checked against caelestia-shell 2.5.0
    (`generalconfig.hpp`: `enabled`, `timeout`, `idleAction`, `returnAction`,
    `inhibitWhenAudio`, `inhibitWhenCharging`, `respectInhibitors`).
  - **Not yet verified on a real machine:** that the shell picks up the edited
    `shell.json` by itself and the suspend monitor stops on a desktop (test with
    a short timeout and `journalctl -b -u systemd-logind`), and that a laptop
    still sleeps when idle on battery.
