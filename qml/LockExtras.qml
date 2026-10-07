pragma Singleton

// Added by caelestia-setup (not part of Caelestia). Installed into the shell's
// services/ folder by patches/patch_shell.py.
//
// Reads ~/.config/caelestia/extras.json, the per-user settings for the
// lock-screen additions. The file is watched, so edits apply straight away:
//
//   {
//     "lock": {
//       "video": "assets/lockscreen.mp4",   // relative to ~/.config/caelestia, or absolute, or ~/...
//       "videoScreens": "largest",          // "largest", "all" or ["DP-2", "HDMI-A-1"]
//       "videoAudio": "once",               // "once", "always" or "off"
//       "panelOpacity": 0.7                 // 0-1; 1 is Caelestia's normal look
//     }
//   }

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    property var settings: ({})

    readonly property var lock: settings?.lock ?? ({})

    readonly property string video: resolve(typeof lock.video === "string" ? lock.video : "")
    readonly property var videoScreens: lock.videoScreens ?? "largest"
    readonly property string videoAudio: ["once", "always", "off"].includes(lock.videoAudio) ? lock.videoAudio : "once"
    readonly property real panelOpacity: {
        const k = Number(lock.panelOpacity ?? 1);
        return k >= 0 && k <= 1 ? k : 1;
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
        if (!video || !screen)
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
