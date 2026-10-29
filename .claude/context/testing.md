# Testing

## Stages

| Stage | What | Status |
|---|---|---|
| 1 | The maintainer's own machine | Done |
| 2 | Private config repo flow (`backup`, `save`, restore at install) | Done |
| 3 | Fresh install for a new user, in a VM | **Not done** |

A full reinstall of the maintainer's machine (Oct 2026, v17) was effectively
the first real fresh-install run, though with an existing private config repo
to restore.

## Waiting on a real-machine test

- v21's fix for black monitors after a Sunshine stream. The plan and what to
  check are in `sunshine.md`.
- v22's MyBudget option on a machine without it: the download and key check
  and the `pacman.conf` lines were tested against the real site, with sudo
  stubbed out. Still to see for real: `pacman -U` adding the key, a later
  `caelestia-setup update` syncing the repo, and Super+B opening the app.
- v23's random lock video from a folder: the pick logic and the folder scan
  were tested headless with Qt (not inside Quickshell). Still to see for
  real: a random video on each lock, the same one on every screen with
  `"videoScreens": "all"`, the first lock after login (lock at boot) showing
  a video, and a new one after waking from sleep.

## Bugs found by fresh installs

None recorded yet. Add each one here with its status, and remove it once
it's fixed and released (the CHANGELOG then records it).
