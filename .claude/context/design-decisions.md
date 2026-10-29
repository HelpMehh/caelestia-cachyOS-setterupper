# Design decisions

Why things work the way they do. Change any of these only on purpose, after
talking it through with the maintainer.

## Shell patches

- `patches/patch_shell.py` edits the installed shell at
  `/etc/xdg/quickshell/caelestia` in place: the lock-screen video, keyring
  unlock, animated profile picture, hiding the lock screen's profile picture
  and monitor fixes.
- Hiding the lock screen's profile picture (`lock.showFace: false`) sets
  `visible` on `ProfilePic` in `modules/lock/Center.qml`. That file is a
  `ColumnLayout`, and layouts leave hidden items out (their margins too), so
  the picture's room goes away and the password box moves up. Lock screen
  only: the dashboard's picture doesn't cover the video.
- Animated profile picture: `qml/FaceImage.qml` replaces `CachingImage` for
  `~/.face` and only switches to `AnimatedImage` when the file has more than
  one frame (checked by loading it at 8x8). Not `AnimatedImage` for
  everything: its `sourceSize` scales to that exact size, squashing
  non-square pictures, so a big still photo would have to load at full size
  instead of shrunk like `CachingImage` does. Animated pictures do play at
  full size, hence the README's "keep it small".
- A pacman hook (`system/caelestia-setup-patch.hook`) re-applies them after
  every shell update. It warns when a patch no longer fits the new shell code
  instead of failing. Status is written to
  `/var/lib/caelestia-setup/patch-status.json`.
- `caelestia-setup unpatch` / `patch` remove and restore them, as the escape
  hatch when the lock screen or bar misbehaves.

## Login ("lock at boot")

- greetd logs in automatically, then Caelestia locks straight away. Unlocking
  also unlocks the keyring. There's no custom greeter.
- Opt-in, and recommended **off** on laptops.

## Monitors

- Automatic by default: native resolution, highest refresh rate.
- The optional `monitors` mode sets order and layout. Syntax: rows separated by
  `/` (`3 / 2 1`), `-` for an empty place, and rotation suffixes `2r`, `2l`,
  `2u`, `2n`.

## Browser theming

- Chrome or Brave colours follow the wallpaper through a root-owned helper
  (`system/browser-theme`), called through a sudo rule that accepts only a
  colour.
- Caelestia's own `enableChromium` must stay **off**. With it on, Chrome's
  background ends up one wallpaper behind.

## Other defaults

- The colour scheme follows the wallpaper by default.
- Discord: the official package, not Caelestia's Equibop.
- MyBudget (a third-party pacman repo, chosen as an extra app): the first
  package comes from the downloaded file and is installed only if its `.sig`
  verifies, in a throw-away GnuPG home, with a primary key equal to the
  fingerprint pinned in `install.sh`. The primary key has no expiry; only its
  subkeys rotate, so the pin lasts. The `.sig` is saved under another name,
  because `pacman -U` would check it against a key it doesn't know yet and
  refuse. The repo is added to `pacman.conf` only after the package is
  installed (its install script runs `pacman-key --populate mybudget`), so
  syncing never meets an unknown key. Its window class is `mybudget`
  (`setDesktopFileName`). The Super+B bind goes in `hypr-user.lua`, not
  `base.lua`: binding the same toggle twice fires it twice, so the key would
  do nothing for anyone who already has it. Update mode installs the package
  and repo only; the workspace is added at install, so one you removed on
  purpose doesn't come back.
- Special-workspace grids: fixed layouts from `extras.json` `"grids"`,
  implemented as Lua layouts in `hypr/base.lua`, with workspace names resolved
  through the `cli.json` toggles.
- Terminal apps from file managers: GLib and Thunar only know a fixed list of
  terminals, so `bin/xdg-terminal-exec` (linked into `/usr/local/bin`) picks
  `$TERMINAL`, then the terminal set in `hypr-vars.lua`, then foot, kitty and
  so on. It replaces an older hand-made copy, recognised by the comment "Lets
  file managers open terminal apps".
- "Show in folder": Thunar's `org.freedesktop.FileManager1` D-Bus service is
  linked into `~/.local/share/dbus-1/services`, because otherwise Dolphin
  answers.
