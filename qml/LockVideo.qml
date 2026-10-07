// Added by caelestia-setup (not part of Caelestia). Installed into the shell's
// modules/lock/ folder by patches/patch_shell.py and loaded by a Loader in
// LockSurface.qml.
//
// It lives in its own file so that QtMultimedia is only imported here: if the
// qt6-multimedia package is ever missing, this component fails to load and
// the lock screen itself still works.

import QtQuick
import QtMultimedia
import qs.services

Item {
    visible: player.hasVideo

    VideoOutput {
        id: videoOut

        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
    }

    // Qt picks the default sound output once, when a player is created, and
    // never follows it. Sunshine creates its virtual display (and with it
    // this player) a moment before it switches the default output to its own,
    // so bind the device to keep up with the switch.
    MediaDevices {
        id: mediaDevices
    }

    MediaPlayer {
        id: player

        property int lastPosition: 0

        source: "file://" + LockExtras.video
        videoOutput: videoOut
        audioOutput: AudioOutput {
            id: audioOut

            device: mediaDevices.defaultAudioOutput
            muted: LockExtras.videoAudio === "off"
        }
        loops: MediaPlayer.Infinite

        // Position jumps back to the start on each loop.
        onPositionChanged: {
            if (LockExtras.videoAudio === "once" && position < lastPosition)
                audioOut.muted = true;
            lastPosition = position;
        }
        Component.onCompleted: play()
    }
}
