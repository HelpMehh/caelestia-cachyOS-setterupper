# Sunshine (game streaming)

## Design

- `capture = wlr`. `global_prep_cmd` runs `bin/sunshine-vd-start` and
  `bin/sunshine-vd-stop`. Start creates a headless `sunshine_vd` output sized
  to the client and turns the real monitors off. Stop restores them.
- The monitor layout is saved in a state file that `hypr/base.lua` re-applies
  on reload.
- Sunshine starts after the shell, because it quits when there's no tray.

## Firewall (ufw)

- TCP 47984, 47989, 48010 and UDP 47998–48000, 48002, 48010 (Sunshine's
  standard ports).
- Allowed from the local network by default. When "Stream from outside your
  home network?" is answered yes (v15), they're open to everyone, UPnP replies
  are allowed (UDP **from** port 1900) and `upnp = enabled` is set. UPnP
  doesn't work without that port-1900 rule.

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
- The planned fix is in `backlog.md`.
