pragma Singleton

// Added by caelestia-setup (not part of Caelestia). Installed into the shell's
// services/ folder by patches/patch_shell.py.
//
// Reads ~/.config/caelestia/extras.json, the per-user settings for the
// lock-screen additions. The file is watched, so edits apply straight away:
//
//   {
//     "lock": {
//       "video": "assets/lockvideos",       // a video file, or a folder of them (one is picked at random);
//                                           // relative to ~/.config/caelestia, or absolute, or ~/...
//       "videoScreens": "largest",          // "largest", "all" or ["DP-2", "HDMI-A-1"]
//       "videoAudio": "once",               // "once", "always" or "off"
//       "panelOpacity": 0.7,                // 0-1; 1 is Caelestia's normal look
//       "showFace": true                    // false hides the profile picture
//     }
//   }

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Models
import qs.utils

Singleton {
    id: root

    property var settings: ({})

    readonly property var lock: settings?.lock ?? ({})

    // lock.video is a video file, or else a folder whose videos (subfolders
    // included) are all picked from. Keep the file types in step with the
    // lock video check in install.sh.
    readonly property var videoTypes: ["mp4", "mkv", "webm", "mov", "avi", "m4v"]
    readonly property string videoPath: resolve(typeof lock.video === "string" ? lock.video : "")
    readonly property bool videoIsFile: videoTypes.includes(videoPath.split(".").pop().toLowerCase())
    readonly property var videos: videoIsFile ? [videoPath] : videoFolder.entries.map(e => e.path)
    readonly property var videoScreens: lock.videoScreens ?? "largest"
    readonly property string videoAudio: ["once", "always", "off"].includes(lock.videoAudio) ? lock.videoAudio : "once"
    readonly property bool showFace: lock.showFace !== false
    readonly property real panelOpacity: {
        const k = Number(lock.panelOpacity ?? 1);
        return k >= 0 && k <= 1 ? k : 1;
    }

    property string picked: ""
    property real pickedAt: 0

    // The video for a player that is starting. Players that start within a
    // few seconds of the last pick share it, so every screen shows the same
    // video, and each lock (or wake-up, which restarts the players) gets a
    // new random one. With more than one video, never the same one twice in
    // a row.
    function pickVideo(): string {
        const now = Date.now();
        if (now - pickedAt > 3000 || !videos.includes(picked)) {
            const others = videos.filter(v => v !== picked);
            const from = others.length ? others : videos;
            picked = from[Math.floor(Math.random() * from.length)] ?? "";
            pickedAt = now;
        }
        return picked;
    }

    function resolve(path: string): string {
        if (!path)
            return "";
        if (path.startsWith("/"))
            return path;
        if (path.startsWith("~/"))
            return Paths.home + path.slice(1);
        return `${Paths.config}/${path}`;
    }

    // Whether the lock video plays on this screen. "largest" picks the screen
    // with the most pixels (leftmost on a tie). During a Sunshine stream the
    // virtual display is the only screen, so it is also the largest.
    function showsVideoOn(screen: ShellScreen): bool {
        if (!videos.length || !screen)
            return false;

        const want = videoScreens;
        if (want === "all")
            return true;
        if (Array.isArray(want))
            return want.includes(screen.name);

        let best = null;
        for (const s of Quickshell.screens) {
            const area = s.width * s.height;
            const bestArea = best ? best.width * best.height : -1;
            if (area > bestArea || (area === bestArea && s.x < best.x))
                best = s;
        }
        return best?.name === screen.name;
    }

    // Fills in a moment after the path is set, which starts the player.
    FileSystemModel {
        id: videoFolder

        path: root.videoIsFile ? "" : root.videoPath
        recursive: true
        nameFilters: root.videoTypes.map(t => `*.${t}`)
    }

    FileView {
        path: `${Paths.config}/extras.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.settings = JSON.parse(text());
            } catch (e) {
                console.warn("caelestia-setup: extras.json is not valid JSON:", e);
            }
        }
        onLoadFailed: root.settings = {}
    }
}
