#!/usr/bin/env python3
"""Apply caelestia-setup's additions to the installed Caelestia shell.

Run as root: by the installer, and by a pacman hook after every install or
upgrade of the caelestia-shell package (which puts the original files back).

Every patch is safe to run again, checks that the code it changes still looks
the way it expects, and is skipped with a warning when it doesn't. The result
of each patch is written to a status file so `caelestia-setup check` and the
login notification can report patches that no longer fit.

Nothing personal is patched in: the lock-screen additions read their settings
from each user's ~/.config/caelestia/extras.json while the shell runs.

Before a file is changed its original is saved, so everything can be undone:

    patch_shell.py --revert     put the original files back and stop patching
                                (the pacman hook then does nothing)
    patch_shell.py --enable     start patching again and apply the additions
"""

import argparse
import json
import os
import pathlib
import re
import shutil
import sys
import time

MARK = "caelestia-setup"

OK, ALREADY, SKIPPED, FAILED = "applied", "already applied", "skipped", "FAILED"

# Text that only appears in a file once one of our patches is in it.
OUR_MARKS = (
    MARK,
    "LockExtras.",
    "id: lockVideo",
    "Hyprland.monitors.values.find(",
    "function reloadShell",
    "QT_AUDIO_BACKEND",
)
ADDED_FILES = (("LockExtras.qml", "services"), ("LockVideo.qml", "modules/lock"))


class Patcher:
    def __init__(self, shell: pathlib.Path, qml: pathlib.Path, orig: pathlib.Path) -> None:
        self.shell = shell
        self.qml = qml
        self.orig = orig
        self.results: dict[str, dict[str, str]] = {}

    def write(self, path: pathlib.Path, text: str) -> None:
        """Change a shell file, keeping its original for --revert. Only an
        unpatched file is saved, so a later patch never overwrites the
        original with an already-patched copy."""

        current = path.read_text()
        if not any(mark in current for mark in OUR_MARKS):
            backup = self.orig / path.relative_to(self.shell)
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup.write_text(current)
        path.write_text(text)

    def revert(self) -> None:
        """Put back every original we saved -- unless the file has since been
        replaced by a package upgrade (then it is already an original, and a
        newer one than ours)."""

        restored = 0
        if self.orig.is_dir():
            for backup in sorted(p for p in self.orig.rglob("*") if p.is_file()):
                target = self.shell / backup.relative_to(self.orig)
                if target.exists() and any(mark in target.read_text() for mark in OUR_MARKS):
                    shutil.copyfile(backup, target)
                    restored += 1
            shutil.rmtree(self.orig)
        for name, dest_dir in ADDED_FILES:
            (self.shell / dest_dir / name).unlink(missing_ok=True)

        leftovers = [
            str(f.relative_to(self.shell))
            for f in self.shell.rglob("*")
            if f.is_file() and f.suffix in (".qml", "") and "pam.d" not in f.parts
            and any(mark in f.read_text(errors="ignore") for mark in OUR_MARKS)
        ]
        if leftovers:
            self.record("revert", FAILED, "still patched, reinstall caelestia-shell: " + ", ".join(leftovers))
        else:
            self.record("revert", OK, f"{restored} file(s) restored")

    def record(self, name: str, state: str, detail: str = "") -> None:
        self.results[name] = {"state": state, "detail": detail}
        line = f"    {name}: {state}"
        if detail:
            line += f" ({detail})"
        print(line)

    # --- new files -------------------------------------------------------

    def add_files(self) -> None:
        """Our own QML files. pacman doesn't own them, so they survive upgrades,
        but they are refreshed on every run in case caelestia-setup changed."""

        for src_name, dest_dir in ADDED_FILES:
            src = self.qml / src_name
            dest = self.shell / dest_dir / src_name
            if not src.exists() or not dest.parent.is_dir():
                self.record(f"add {src_name}", FAILED, f"missing {src if not src.exists() else dest.parent}")
                continue
            if dest.exists() and dest.read_bytes() == src.read_bytes():
                self.record(f"add {src_name}", ALREADY)
                continue
            shutil.copyfile(src, dest)
            os.chmod(dest, 0o644)
            self.record(f"add {src_name}", OK)

    # --- lock screen video -----------------------------------------------

    def lock_video(self) -> None:
        name = "lock video"
        p = self.shell / "modules/lock/LockSurface.qml"
        if not p.exists():
            return self.record(name, FAILED, "LockSurface.qml not found")
        s = p.read_text()
        if "id: lockVideo" in s:
            return self.record(name, ALREADY)

        anchor = "    Component {\n        id: screencopyBackground"
        if s.count(anchor) != 1 or "id: background" not in s:
            return self.record(name, FAILED, "LockSurface.qml changed upstream")

        block = f"""    // Lock screen video ({MARK}). The player is in LockVideo.qml; which
    // file plays, on which screens and with what sound comes from
    // ~/.config/caelestia/extras.json (see services/LockExtras.qml).
    // It sits above Caelestia's blurred background, fades with it, and is
    // destroyed on unlock.
    Loader {{
        id: lockVideo

        property bool restarting: false

        // Tear the player down and build a new one: the video starts over
        // on a fresh decoder.
        function restart(): void {{
            restarting = true;
            Qt.callLater(() => lockVideo.restarting = false);
        }}

        anchors.fill: parent
        opacity: background.opacity
        active: !restarting && LockExtras.showsVideoOn(root.screen)
        source: Qt.resolvedUrl("LockVideo.qml")
    }}

    // Replay the video when the PC wakes up. Caelestia locks just before
    // sleep, so the player starts as the PC goes down and comes back mid-way
    // (or with a decoder the suspend broke). Timers don't count time spent
    // suspended but the wall clock does, so a big jump between ticks means
    // the PC just resumed.
    Timer {{
        id: lockVideoWake

        property real lastTick: Date.now()

        interval: 1000
        running: lockVideo.active
        repeat: true
        onTriggered: {{
            const now = Date.now();
            if (now - lastTick > 5000)
                lockVideo.restart();
            lastTick = now;
        }}
    }}

"""
        self.write(p, s.replace(anchor, block + anchor, 1))
        self.record(name, OK)

    # --- lock panel opacity ----------------------------------------------

    def lock_opacity(self) -> None:
        """Let the video show through the lock screen's panel and its cards.
        Only backgrounds fade, and only on the lock screen."""

        name = "lock panel opacity"
        p = self.shell / "modules/lock/LockSurface.qml"
        if not p.exists():
            return self.record(name, FAILED, "LockSurface.qml not found")
        s = p.read_text()

        old = "opacity: Colours.transparency.enabled ? Colours.transparency.base : 1\n"
        new = (
            "opacity: LockExtras.panelOpacity * (Colours.transparency.enabled ? Colours.transparency.base : 1)"
            f" // {MARK}\n"
        )
        panel_done = "LockExtras.panelOpacity" in s
        if not panel_done:
            if s.count(old) != 1:
                return self.record(name, FAILED, "lock panel changed upstream")
            self.write(p, s.replace(old, new, 1))

        # The cards (clock, weather, media, password box...) use the
        # transparency-aware palette; scale their alpha as well.
        cards = 0
        pattern = re.compile(r"Colours\.tPalette\.(\w+)")
        for f in sorted((self.shell / "modules/lock").rglob("*.qml")):
            t = f.read_text()
            if "LockExtras.panelOpacity)" in t:
                continue  # already scaled
            if "import qs.services" not in t:
                continue  # LockExtras wouldn't resolve there
            t2, n = pattern.subn(
                r"Qt.alpha(Colours.tPalette.\1, Colours.tPalette.\1.a * LockExtras.panelOpacity)", t
            )
            if n:
                self.write(f, t2)
                cards += n

        if panel_done and not cards:
            return self.record(name, ALREADY)
        self.record(name, OK, f"{cards} card colour(s) scaled")

    # --- keyring unlock --------------------------------------------------

    def keyring(self) -> None:
        """Unlocking the lock screen also unlocks the GNOME keyring. Caelestia's
        lock uses its own PAM file, which only checks the password. With lock
        at boot there is no login prompt to unlock the keyring, so without
        this the first app that wants a saved password asks for it again."""

        name = "keyring unlock"
        pam = self.shell / "assets/pam.d/passwd"
        module_dirs = ("/usr/lib/security", "/lib/security", "/usr/lib64/security")
        if not any(os.path.exists(f"{d}/pam_gnome_keyring.so") for d in module_dirs):
            return self.record(name, SKIPPED, "gnome-keyring's PAM module isn't installed")
        if not pam.exists():
            return self.record(name, FAILED, "assets/pam.d/passwd not found")
        s = pam.read_text()
        if "pam_gnome_keyring" in s:
            return self.record(name, ALREADY)
        if "pam_unix.so" not in s:
            return self.record(name, FAILED, "PAM file changed upstream")
        if not s.endswith("\n"):
            s += "\n"
        self.write(pam, s + f"auth    optional                    pam_gnome_keyring.so  # {MARK}\n")
        self.record(name, OK)

    # --- reactive monitor lookup -----------------------------------------

    def monitor_lookup(self) -> None:
        """Upstream uses Hyprland.monitorFor(), a one-shot lookup: a screen whose
        windows are created before Quickshell hears about its monitor (a race
        when monitors come back after a stream) keeps a null monitor until the
        shell restarts. The bar then blurs its workspaces and clicks near the
        screen edges stop reaching windows. Looking the monitor up through
        Hyprland.monitors re-runs every binding when the monitor shows up."""

        name = "reactive monitor lookup"
        p = self.shell / "services/Hypr.qml"
        if not p.exists():
            return self.record(name, FAILED, "services/Hypr.qml not found")
        s = p.read_text()
        if "Hyprland.monitors.values.find(" in s:
            return self.record(name, ALREADY)
        old = "        return Hyprland.monitorFor(screen);\n"
        if s.count(old) != 1:
            return self.record(name, FAILED, "Hypr.monitorFor changed upstream")
        new = (
            f"        // Reactive lookup ({MARK}): re-evaluates when monitors are added.\n"
            "        return Hyprland.monitors.values.find(m => m.name === screen?.name)"
            " ?? Hyprland.monitorFor(screen);\n"
        )
        self.write(p, s.replace(old, new, 1))
        self.record(name, OK)

    # --- reloadShell command ---------------------------------------------

    def reload_shell(self) -> None:
        """qs -c caelestia ipc call hypr reloadShell: rebuild the shell's
        windows. The Sunshine stop script calls it after a stream."""

        name = "reloadShell command"
        p = self.shell / "services/Hypr.qml"
        if not p.exists():
            return self.record(name, FAILED, "services/Hypr.qml not found")
        s = p.read_text()
        if "function reloadShell" in s:
            return self.record(name, ALREADY)
        anchor = '        target: "hypr"\n'
        if s.count(anchor) != 1:
            return self.record(name, FAILED, "hypr IPC handler changed upstream")
        fn = (
            f"        // Added by {MARK}: rebuild the shell's windows.\n"
            "        function reloadShell(): void {\n"
            "            Qt.callLater(() => Quickshell.reload(false));\n"
            "        }\n\n"
        )
        self.write(p, s.replace(anchor, fn + anchor, 1))
        self.record(name, OK)

    # --- audio backend ---------------------------------------------------

    def audio_backend(self) -> None:
        """Qt 6.10+ plays sound through its own PipeWire code by default, and
        that code crashes the whole shell when the output it is playing to
        disappears -- which is what happens to the lock video when a Sunshine
        stream ends and Sunshine removes its sound output. Hyprland then shows
        "the lockscreen app died". Qt's PulseAudio code (served by PipeWire
        all the same) handles a vanishing output, so make the shell use it.
        DefaultEnv leaves a value you set yourself alone."""

        name = "audio backend"
        p = self.shell / "shell.qml"
        s = p.read_text()
        if "QT_AUDIO_BACKEND" in s:
            return self.record(name, ALREADY)
        lines = s.split("\n")
        pragmas = [i for i, line in enumerate(lines) if line.startswith("//@ pragma ")]
        if not pragmas:
            return self.record(name, FAILED, "shell.qml has no pragma lines; it changed upstream")
        # No trailing comment: everything after "=" is taken as the value.
        lines.insert(pragmas[-1] + 1, "//@ pragma DefaultEnv QT_AUDIO_BACKEND=pulseaudio")
        self.write(p, "\n".join(lines))
        self.record(name, OK)

    def run(self) -> None:
        self.add_files()
        self.audio_backend()
        self.lock_video()
        self.lock_opacity()
        self.keyring()
        self.monitor_lookup()
        self.reload_shell()


def main() -> int:
    here = pathlib.Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--shell-dir", default="/etc/xdg/quickshell/caelestia", type=pathlib.Path)
    ap.add_argument("--qml-dir", default=here.parent / "qml", type=pathlib.Path)
    ap.add_argument("--state-dir", default="/var/lib/caelestia-setup", type=pathlib.Path)
    ap.add_argument("--revert", action="store_true", help="restore the original files and stop patching")
    ap.add_argument("--enable", action="store_true", help="start patching again (undoes --revert)")
    args = ap.parse_args()
    status_file = args.state_dir / "patch-status.json"
    disabled = args.state_dir / "disabled"

    if not (args.shell_dir / "shell.qml").exists():
        print(f"caelestia-setup: no shell found in {args.shell_dir}; nothing to do")
        return 0

    patcher = Patcher(args.shell_dir, args.qml_dir, args.state_dir / "orig")
    try:
        args.state_dir.mkdir(parents=True, exist_ok=True)
        if args.enable:
            disabled.unlink(missing_ok=True)
        if args.revert:
            print("caelestia-setup: removing the additions from the Caelestia shell")
            disabled.write_text("Shell additions were turned off with --revert. Turn them on with --enable.\n")
            patcher.revert()
        elif disabled.exists():
            print("caelestia-setup: shell additions are turned off (caelestia-setup patch turns them on)")
            return 0
        else:
            print("caelestia-setup: patching the Caelestia shell")
            patcher.run()
    except OSError as e:
        patcher.record("patching", FAILED, str(e))

    failed = [n for n, r in patcher.results.items() if r["state"] == FAILED]
    try:
        tmp = status_file.with_suffix(".tmp")
        status = {"time": int(time.time()), "reverted": args.revert, "failed": failed, "results": patcher.results}
        tmp.write_text(json.dumps(status, indent=2))
        os.chmod(tmp, 0o644)
        tmp.replace(status_file)
    except OSError as e:
        print(f"    could not write {status_file}: {e}", file=sys.stderr)

    if failed and not args.revert:
        print("    WARNING: these additions no longer fit this version of the shell: " + ", ".join(failed))
        print("    The shell still works without them. Run `caelestia-setup check` for details.")
    # Always succeed: a patch that doesn't fit must never fail a system update.
    return 0


if __name__ == "__main__":
    sys.exit(main())
