# Changelog

What each version of `caelestia-setup` changed, newest first. Install a new
version with `caelestia-setup update`. Versions before v9 aren't listed here;
see the git history.

## v23

- The lock screen can pick a random video each time it locks, like the
  wallpapers. Set `lock.video` in `extras.json` to a folder (for example
  `"assets/lockvideos"`) instead of a single file. Every screen shows the same
  video, and the same one never plays twice in a row. Waking from sleep
  starts a new one. Sound, screens and transparency still apply to all
  videos. A single file works as before.
- Lock videos with `#` or `?` in their file name now play.
- `check` counts the videos in a lock video folder, and flags a `lock.video`
  file that isn't a video type the lock screen plays.

## v22

- New extra app at the install questions: `mybudget`, a budgeting app. It's
  installed from its own repository, which is added to pacman, so
  `caelestia-setup update` keeps it up to date. Before installing, the
  download is checked against MyBudget's signing key. `qt6-tools` comes with
  it, for the in-app help.
- MyBudget gets its own workspace on Super+B. It opens
  `~/Documents/Budget/mybudget.mbgt` (created the first time). Added only
  where there's no "budget" workspace and no Super+B in your settings yet.
- `check` shows whether MyBudget and its repository are in place, if you
  chose it.

## v21

- Fixed the monitors sometimes staying black after a Sunshine stream, mostly
  after leaving a stream running and reconnecting to it a few times, or
  closing the app before it had finished quitting. A second stream start
  could forget which monitors to switch back on. Now it remembers them, and
  if no monitor comes back when a stream ends, the normal monitor layout is
  reloaded. Sunshine's log notes which monitors each stream turned off.

## v20

- Thunar can zip and unzip files from the right-click menu, and shows USB
  drives and other disks in its side panel, ready to open with a click. This
  installs `thunar-archive-plugin` and `file-roller` (archives), and `gvfs`,
  `udisks2` and `thunar-volman` (drives), only where Thunar is installed.
  `update` adds any that are missing on existing installs, and `check` shows
  whether they're there.

## v19

- Screenshots saved from swappy (the editor that opens after a region
  screenshot) go to `~/Pictures/Screenshots`, next to Caelestia's own
  screenshots, instead of the Desktop. A save folder you've set in swappy
  yourself is kept. `update` sets this up on existing installs too, and
  `check` shows whether it's in place.

## v18

- When `update` installs a new version of `caelestia-setup`, it now carries on
  with the new version straight away. Before, the rest of that update still
  ran the old version, so fixes only arrived with the next update. (This
  starts working with the update *after* the one that installs v18.)
- The PC no longer goes to sleep during a Sunshine stream, even when you
  aren't touching anything (watching a video, a paused game). The block ends
  when the stream does.
- With Sunshine streaming from outside switched on, a desktop no longer goes
  to sleep when idle, so it stays reachable between streams. A laptop still
  does, but only on battery. This is set in `shell.json` (only where you
  haven't set it yourself), and `check` points it out if it's missing.

## v17

- File managers (Thunar and others) can open terminal apps. A small
  `xdg-terminal-exec` helper picks your terminal: `$TERMINAL`, then the one set
  in your Hyprland variables, then foot, kitty and so on.
- "Show in folder" in browsers opens Thunar instead of Dolphin.
- `update` no longer stops when your settings mention an app that isn't in the
  repositories.
- `update` no longer fails when Sunshine isn't installed.
- `update` now also refreshes the terminal helper and the "Show in folder"
  set-up every time.

## v16

- Special workspaces can have fixed window layouts, set with `"grids"` in
  `extras.json`.

## v15

- New question: "Stream from outside your home network?" When you answer yes,
  Sunshine's ports are opened to everyone and UPnP is turned on.

## v14

- The repository was renamed from `caelestia-default-config` to
  `caelestia-cachyOS-setterupper`.

## v13

- Discord is installed from the official package.

## v12

- The colour scheme follows the wallpaper by default.

## v11

- `caelestia-setup monitors` handles screens in several rows, empty places and
  rotated screens.

## v10

- The docs say to update only with `caelestia-setup update`.

## v9

- System updates are held back while a new Qt version is only half-published
  (that once broke the shell).
- Sunshine starts after the shell, because it quits when there's no tray.
