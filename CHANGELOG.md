# Changelog

What each version of `caelestia-setup` changed, newest first. Install a new
version with `caelestia-setup update`. Versions before v9 aren't listed here;
see the git history.

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
