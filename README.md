# caelestia-cachyOS-setterupper

Sets up the [Caelestia](https://github.com/caelestia-dots/caelestia) desktop on
**CachyOS**, with a few additions, in one command. It is a personal project
and is not part of Caelestia or CachyOS.

The only requirement is CachyOS installed with its **Hyprland** desktop. It
does not matter what hardware you have or what your user name is.

## Install

Open a terminal and paste:

```sh
curl -fsSL https://raw.githubusercontent.com/HelpMehh/caelestia-default-config/main/install.sh | bash
```

Running it means trusting this repository's owner: the script installs
software and changes system settings. Read "What it changes on the system"
below first.

It asks a few questions first (each has a safe default: press Enter), shows
what it is about to do, and waits for your go-ahead:

| Question | What it means |
|---|---|
| Saved settings | If you used this before: bring your settings back from your private GitHub repository. |
| Browser | Firefox, Chrome, Brave, Opera or none. Firefox, Chrome and Brave follow the desktop colours. |
| Sunshine | Stream this desktop to a phone, tablet or TV with the Moonlight app. |
| Lock at boot | Log in automatically and show the lock screen straight away. Say no on a laptop. |
| Extra apps | Apps Caelestia can install and theme (Neovim, Spotify, VS Code...). |
| Monitor order | Only with more than one screen: which is left, middle, right. |

During the install, `paru` shows the build script of each community (AUR)
package. Press `q` to close it and `y` to continue.

## What it adds to plain Caelestia

- A video behind the lock screen, with adjustable transparency of the lock
  panel. Off until you choose a video.
- Unlocking the lock screen also unlocks your saved passwords (keyring).
- Fixes for the bar and screen edges after monitors are switched off and on.
- Every screen at its highest refresh rate, and a saved layout per computer.
- Optional: Sunshine with a virtual display sized to the device you stream to.
  Your real monitors switch off during a stream and come back afterwards.
- Optional: Chrome or Brave follow the wallpaper's colours; Chrome's new tab
  page shows the wallpaper.
- A hook that puts these additions back after every Caelestia update.
- `caelestia-setup update` rebuilds Quickshell when a system update brings a
  newer Qt, which would otherwise leave you without a bar or lock screen.
- `caelestia-setup update` looks at what a system update would change before
  running it. Qt is published as many packages that only work at one version;
  if the package servers hold a new Qt half-published, the system update is
  skipped that time and you are told to try again later.

## Discord

Choosing `discord` at the apps question installs the official Discord app
from CachyOS's repositories. Caelestia's own "discord" part installs Equibop,
a modified client, which its communication-workspace toggle does not start;
that part is left off. The official app is not recoloured with the wallpaper.

## Updating

Update with `caelestia-setup update`, and only with that. It runs the full
system update (CachyOS's packages, AUR packages and Caelestia), so nothing
else is needed, and it is the only way of updating that first makes sure the
update would not leave the desktop unable to start. `pacman -Syu`, `paru` and
software centres do the same update without that protection.

It does not cover Flatpaks, firmware, or apps that update themselves (Steam,
for one).

## Afterwards

```sh
caelestia-setup update      # update the system, Caelestia and this set-up
caelestia-setup save        # upload your settings to your private GitHub repository
caelestia-setup backup      # set that repository up (once)
caelestia-setup check       # test that everything is in place
caelestia-setup monitors    # save this computer's monitor layout again
caelestia-setup unpatch     # remove the shell additions ("patch" restores them)
```

Your own settings are the files in `~/.config/caelestia`. Nothing in this
repository is personal, and the installer never overwrites a file you already
have there.

| File | For |
|---|---|
| `extras.json` | Lock video, lock transparency, lock at login, wallpaper change at login |
| `hypr-user.lua` | Your own Hyprland settings. Keep its first line. |
| `hypr-vars.lua` | Caelestia's variables: default apps, keybinds, gaps |
| `shell.json`, `cli.json` | Caelestia's own settings ([shell](https://github.com/caelestia-dots/shell), [CLI](https://github.com/caelestia-dots/cli)) |
| `machines/<computer>.lua` | That computer's monitor layout |
| `setup-answers` | Your answers to the installer's questions |
| `wallpapers/` | Your wallpapers |

## Backing up your settings

Your settings, wallpapers and lock video can live in a **private** GitHub
repository that only you can see. `~/.config/caelestia` is the working copy
of it: you change the live files (or use Caelestia's settings window), and
upload when you like.

```sh
caelestia-setup backup      # once: sign in to GitHub, create the private repository, first upload
caelestia-setup save        # afterwards: show what changed and upload it
```

`backup` offers two ways to reach GitHub. Signing in through the browser is
the simple one. The other makes a key that can reach only that one
repository; it is tighter, and you create the repository and paste the key
into its settings yourself.

On a new computer, or after reinstalling, run the install line and answer
yes to "Bring back saved settings from GitHub?". Your settings are
downloaded first, and your earlier answers become the defaults for the other
questions. With two computers, `caelestia-setup update` on one brings in what
the other saved.

Apps that your settings refer to (the player for recordings, the apps behind
your workspace toggles, your editor) are checked after a restore and on every
update. Missing ones are offered for installation when CachyOS's own
repositories have them under the same name; others are listed for you to
install yourself.

Not included: Sunshine's paired devices and login, and your browser profile.
GitHub refuses single files over 100 MB.

To use a lock video, put the file in `~/.config/caelestia/assets/` and set it
in `extras.json`:

```json
{
    "scheme": "dynamic",
    "lock": {
        "atLogin": false,
        "video": "assets/lockscreen.mp4",
        "videoScreens": "largest",
        "videoAudio": "once",
        "panelOpacity": 0.7
    },
    "wallpaperOnLogin": true
}
```

`scheme` is the colour scheme a fresh install starts with (`"dynamic"` follows
the wallpaper). `videoScreens` is `"largest"`, `"all"` or a list of screen names.
`videoAudio` is `"once"`, `"always"` or `"off"`. Changes apply immediately.

## What it changes on the system

So you know what you are running:

- On a system with no password store yet, creates one locked with your login
  password, so it unlocks at login. For that it asks for your password
  itself, checks it with `sudo`, and does not keep it.
- Installs packages with `pacman` and `paru`, including Caelestia's own
  installer, which installs its package list.
- Replaces `~/.config/hypr` (CachyOS's Hyprland settings) with Caelestia's.
- Uninstalls CachyOS's Noctalia shell and the apps that only came with it.
- Copies itself to `/usr/local/lib/caelestia-setup` (owned by root) and adds
  the `caelestia-setup` command.
- Replaces Noctalia's Quickshell fork with the real Quickshell from the AUR.
- Edits the Caelestia shell's files in `/etc/xdg/quickshell/caelestia`. The
  originals are kept, and `caelestia-setup unpatch` restores them.
- Adds a pacman hook in `/etc/pacman.d/hooks/`.
- Rewrites `/etc/greetd/config.toml` (the login screen). The original is kept
  next to it.
- With Chrome or Brave: one sudo rule that lets a small helper set the
  browser's theme colour without a password. The helper accepts a colour and
  nothing else.
- With Sunshine: installs it from CachyOS's repositories, and opens its ports
  to home network addresses if the firewall is on.
- Adds two "optional" lines to `/etc/pam.d/greetd` so the text login unlocks
  your saved passwords. The original is kept next to it.
- With a backup: installs GitHub's command-line tool and stores your GitHub
  sign-in (or a single-repository key in `~/.ssh`) on this computer.

## Monitor layouts

`caelestia-setup monitors` lists the screens with numbers and asks how they
sit on the desk. The answer is a small picture of the desk:

| Answer | Meaning |
| --- | --- |
| `2 1 3` | one row, left to right |
| `3 / 2 1` | rows from top to bottom: 3 sits above 2 and 1, centred |
| `- 3 / 2 1` | `-` is an empty place: 3 sits above 1 only |
| `1 2r` | 2 is turned on its side (`l` turns it the other way, `u` is upside down, `n` back to normal) |

Each screen keeps its resolution and scale and gets its highest refresh rate.
The result is saved as `machines/<computer>.lua` and can be edited by hand.

## If something goes wrong

- The installer stops at the first error and can be run again; finished steps
  are skipped or repeated safely.
- If the bar is missing after a system update, run `caelestia-setup check`.
  "Qt's packages are at mixed versions" means the update caught a new Qt
  half-published; the check prints the command that puts it right. (To skip
  the look-ahead described above, set `CS_SKIP_QT_CHECK=1`.)
- If the lock screen or bar misbehaves after an update, press Ctrl+Alt+F3,
  log in, run `caelestia-setup unpatch`, then `systemctl reboot`.
