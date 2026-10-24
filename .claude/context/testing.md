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

## Bugs found by fresh installs

None recorded yet. Add each one here with its status, and remove it once
it's fixed and released (the CHANGELOG then records it).
