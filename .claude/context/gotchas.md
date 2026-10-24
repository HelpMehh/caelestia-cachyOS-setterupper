# Gotchas

## In this installer

- **Self-update restarts the script (since v18).** bash keeps reading the old
  file after `step_system_files` replaces it, so `mode_update` `exec`s the new
  `install.sh` (`update_restart`) with `CAELESTIA_SETUP_RESUME=1` plus
  `QT_HELD` / `SHELL_CHANGED`, and the new version runs only `update_finish`.
  The *old* version sets that variable, so **every future version must keep
  honouring it**. Anything that runs before the self-update (system update,
  Qt guard and rebuild) still runs the old code; put new work in
  `update_finish` when it should take effect on the first run. Updating from
  v17 or older doesn't restart yet, because those versions don't know how.
- **`set -Eeuo pipefail` traps.** A command that's allowed to fail (for
  example `pacman -Si` for an app missing from the repos) must be guarded
  (`|| true`, `if`), or the ERR trap ends the whole run. v17 fixed one of
  these in `find_missing_settings_apps`.
- Steps that touch optional apps (for example `sunshine_unit`) must cope with
  the app not being installed.

## Debugging from the sandbox

- The sandbox user can't read the maintainer's user journal, runtime
  directory or Hyprland socket, and that's on purpose. Evidence such as
  `journalctl --user`, `hyprctl` or files in `$XDG_RUNTIME_DIR` has to come
  from the maintainer. Ask for the exact commands' output early, in fish
  syntax, rather than fixing on a guess.

## Caelestia and Hyprland

- **`hyprctl monitors` lists enabled monitors only.** Disabled ones need
  `hyprctl monitors all`. Monitors with DPMS off are still listed. A config
  reload throws away monitor rules set at run time with `hyprctl eval`.
- **`hyprctl` in a TTY** has no `HYPRLAND_INSTANCE_SIGNATURE`. Use
  `hyprctl instances`, then `hyprctl -i 0 …`.

- **Special-workspace toggles relaunch apps whose window match fails,** even
  while closing the workspace: `toggle()` in
  `~/.config/hypr/utils/functions.lua` always runs `place_apps()`. For a
  single-instance app, the relaunch focuses its existing window, which reopens
  the workspace. So a wrong `class` in a `cli.json` toggle looks like "the
  workspace won't close".
  - Check real classes with
    `hyprctl clients -j | jq -r '.[] | "\(.class) | \(.title) | \(.workspace.name)"'`.
  - The Claude desktop app's class is `com.anthropic.Claude`, not
    `claude-desktop`.

## CachyOS and hardware

- **`sshd` isn't enabled by default** on CachyOS. Any SSH feature must enable
  it explicitly.
- **Dual-boot next to Windows:** Windows keeps the hardware clock in local
  time. The CachyOS installer's pacman keyring step can then fail with "key
  created … seconds in the future". Fix: recreate the keyring once the clock
  has synced, then set `RealTimeIsUniversal=1` in Windows.
- **Multi-device btrfs can make `fsync` very slow:** ~400 ms per call against
  0.5 ms on single-device btrfs or ext4 on the same NVMe drive. The kernel
  stack waits in `btrfs_sync_log → write_all_supers`. It shows up as editors
  lagging while typing (LazyVim's `updatetime=200` writes a swap file
  constantly). If the installer ever gives disk advice, recommend a single
  device.
- **Slow shell start (seen on Ubuntu, not on CachyOS so far):** Quickshell's
  portal request activated power-profiles-daemon, which waited about 8 s on
  `plymouth-quit-wait`. The fix there was masking power-profiles-daemon and
  dropping `splash` from the kernel command line.
- **Qt half-published:** a new Qt once arrived in the repos only partly
  published and broke the shell. Since v9 the update holds back while that's
  the case.
