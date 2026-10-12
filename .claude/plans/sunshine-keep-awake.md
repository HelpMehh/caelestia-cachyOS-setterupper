# Plan: keep the PC awake for Sunshine (v18)

## Context

- Remote streams were dropping because Caelestia suspended the PC while it
  was idle (`sunshine.md`, "Idle, lock and suspend"). "Keep awake" doesn't
  help, because its Wayland inhibitor sits on an invisible window and the
  real monitors are off during a stream.
- **Test result (2026-10, v18):** input through a stream (Artemis) counts as
  activity. Over 6 minutes of use through the stream only, the PC neither
  locked (180 s) nor turned the screen off (300 s). So lock and screen-off
  need nothing. Only **suspend** is a problem: during a stream with no input
  (watching a video, a paused game), and **between streams**, where a
  suspended PC can't be reached from outside. Waking it over the internet
  generally doesn't work.
- How Caelestia suspends (`modules/IdleMonitors.qml` in the shell): each
  entry in `general.idle.timeouts` is an `IdleMonitor`. The suspend entry's
  `idleAction` is `["suspendThenHibernate"]`, run through
  `SessionManager.exec`, so it's a request to logind. Each entry may have
  `inhibitWhenCharging` and `inhibitWhenAudio`. `inhibitWhenCharging` means
  "not while `!UPower.onBattery`", and **a desktop is never on battery**.
- **Why not the backlog's "Allow this PC to sleep when idle?" question:**
  `shell.json` lives in the private config repo, so it's shared by all of a
  user's computers. A "no" answered on the desktop would also stop the
  laptop from ever sleeping on battery. Setting `inhibitWhenCharging` on the
  suspend entry instead gives per-machine behaviour from one shared file:
  - desktop: never suspends when idle
  - laptop: suspends when idle only on battery
  No new installer question is needed (rule: as few questions as possible).

## Steps

### 1. Block sleep while a stream is running

- `bin/sunshine-vd-start`: start
  `systemd-inhibit --what=sleep --mode=block --who=Sunshine --why="Streaming" sleep infinity`
  in the background, and save its PID in `$XDG_RUNTIME_DIR/sunshine_vd.inhibit`.
  First kill a stale one from that file, if any. Keep it in Sunshine's
  cgroup (plain `&`, no `setsid`/`systemd-run`), so a Sunshine crash or
  restart also ends it.
- `bin/sunshine-vd-stop`: kill the PID from the file and delete the file.
  Do this early, before the monitor restore, so a failure later in the
  script can't leave the block behind.
- Covers every machine and every answer to "stream from outside", including
  laptops on battery.
- **Verify on a real machine:**
  - During a stream, `systemd-inhibit --list` shows the block.
  - Caelestia's idle suspend is refused. Set a short suspend timeout in
    `shell.json` to test, and look for a refused request in
    `journalctl -b -u systemd-logind`.
  - After the stream the block is gone, including after
    `systemctl --user restart <sunshine unit>` mid-stream.
  - Note whether "Suspend" in Caelestia's power menu is also refused during
    a stream. That's acceptable, but worth recording.
- CHANGELOG v18 entry. `sunshine.md`: replace the "planned fix" line with
  what was built.

### 2. No idle suspend on desktops that stream from outside

- New `step_idle_sleep` in `install.sh`. It runs when
  `SUNSHINE == yes && SUNSHINE_REMOTE == yes`, from `mode_install` (after
  `step_sunshine`) and from `update_finish` (next to the existing remote
  block, so v18 machines get it on update).
- Editing `$CFG/shell.json` with `json_edit` (add only, never overwrite):
  - If `general.idle.timeouts` **exists**: for each entry whose `idleAction`
    names a suspend/hibernate action (`suspend`, `hibernate`,
    `suspendThenHibernate`, …), set `inhibitWhenCharging: true` **only if the
    key is missing**. A user who set it to `false` on purpose keeps that.
  - If it **doesn't exist**: write Caelestia's default list (lock 180 s,
    `dpms off`/`dpms on` 300 s, `["suspendThenHibernate"]` 600 s), with
    `inhibitWhenCharging: true` on the suspend entry. Check the defaults
    against the installed version of
    `plugin/src/Caelestia/Config/generalconfig.hpp` (or its QML defaults)
    first, and check the exact key spelling the config parser accepts.
  - Say what changed in one `info` line. Do nothing when the answer is "no"
    (don't undo an earlier change; the user may have wanted it).
- **Verify:**
  - Caelestia reloads `shell.json` by itself and the suspend monitor stops on
    a desktop. Test with a short timeout.
  - `UPower.onBattery` is false on a desktop. If UPower isn't running, the
    entry is also skipped, which is still safe for a desktop.
  - On a laptop, if one is available: idle suspend still happens on battery.
- `mode_check`: a NOTE (not a FAIL) when remote streaming is on but the
  suspend entry would still fire on mains power.
- README Sunshine section: one or two sentences. With "stream from outside"
  on, a desktop no longer sleeps when idle (so it stays reachable), and a
  laptop only sleeps on battery. Mention that it's the
  `inhibitWhenCharging` setting in `shell.json`, for anyone who wants it
  back.
- CHANGELOG v18 entry. `sunshine.md`: record the design and test results.
  `backlog.md`: remove the item. Delete this plan.
