# Backlog (v18 candidates)

Remove items when they're released. Undecided items need the maintainer's
decision before planning.

## Keep the PC awake during Sunshine streams

Background in `sunshine.md` ("Idle, lock and suspend").

- `sunshine-vd-start` starts
  `systemd-inhibit --what=sleep --mode=block --who=sunshine --why="Streaming" sleep infinity &`
  and saves its PID in a state file. `sunshine-vd-stop` kills it. logind then
  refuses Caelestia's suspend request while streaming.
- Consider an installer question "Allow this PC to sleep when idle?",
  defaulting to **no** when "stream from outside your home network" is yes.
  It would write an idle timeout list without suspend into `shell.json`.
- **Open question:** does input through a stream count as activity for
  Caelestia's lock (180 s) and screen-off (300 s) timers? If not, screen-off
  may black out the stream, and the prep commands must handle that too.

## NVIDIA fixes (undecided)

See `nvidia-browsers.md`.

- On NVIDIA machines with Chrome or Brave installed, add the video flag if
  it's missing. The maintainer hasn't decided whether this belongs in the
  installer.
- Optionally set `WEBKIT_DISABLE_DMABUF_RENDERER=1`.

## Caps Lock as Super for Sunshine's virtual keyboard (optional)

Android Moonlight clients swallow the Super key (Moonlight issue 975). Map
Caps Lock to Super only for Sunshine's virtual keyboard.

## Sunshine diagnostics mode

A read-only `caelestia-setup` mode that reports service state, recent journal,
sleep events, inhibitors, monitors and network state.

## Stage 3 test

See `testing.md`.
