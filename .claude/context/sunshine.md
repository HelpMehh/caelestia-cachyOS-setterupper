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
- The planned fix is in `backlog.md`.
