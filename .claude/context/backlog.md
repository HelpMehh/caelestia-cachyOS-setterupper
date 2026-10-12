# Backlog (v18 candidates)

Remove items when they're released. Undecided items need the maintainer's
decision before planning.

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
It should also flag a hung HTTPS port: a Recv-Q on 47984 that stays above 0
(see `sunshine.md`, "Pairing and remote connections"), and suggest
restarting Sunshine.

Ideas from the pairing investigation, only worth doing if remote pairing
causes trouble again:

- Recommend "pair at home first" in the README's Sunshine section. Pairing
  is once per device, and the client keeps it when the address changes to a
  domain.
- If UPnP proves unreliable on some routers, say so in the install summary
  and README, and list the ports to forward by hand.
- The local-network ufw rules are IPv4-only. If remote streaming over IPv6
  ever matters, check that ufw has `IPV6=yes` and the rules cover v6.

## Stage 3 test

See `testing.md`.
