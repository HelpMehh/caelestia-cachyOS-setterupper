// Added by caelestia-setup (not part of Caelestia). Installed into the shell's
// components/images/ folder by patches/patch_shell.py, and used in place of
// CachingImage for the profile picture (~/.face) on the lock screen and the
// dashboard.
//
// Still pictures go through Caelestia's own CachingImage, as before: it
// shrinks them to the size shown. An animated GIF or WebP plays through
// AnimatedImage instead, at its own size: AnimatedImage can only shrink to
// an exact size, which squashes pictures that aren't square. A quick look at
// the file at 8x8 pixels tells which of the two it is.

import QtQuick

Item {
    id: root

    property string path
    // Same meaning as Image.status, which the shell's code checks.
    readonly property int status: picture.item?.status ?? Image.Null

    property bool checked: false
    property bool animated: false

    // Counts the frames, then lets go of the file.
    AnimatedImage {
        id: probe

        visible: false
        source: root.path
        sourceSize: Qt.size(8, 8)
        asynchronous: true
        cache: false
        playing: false
        onStatusChanged: {
            if (status === Image.Ready || status === Image.Error) {
                root.animated = status === Image.Ready && frameCount > 1;
                root.checked = true;
                source = "";
            }
        }
    }

    Loader {
        id: picture

        anchors.fill: parent
        active: root.checked
        sourceComponent: root.animated ? animatedPicture : stillPicture
    }

    Component {
        id: stillPicture

        CachingImage {
            path: root.path
        }
    }

    Component {
        id: animatedPicture

        AnimatedImage {
            source: root.path
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            // Pause while the dashboard is closed.
            playing: visible
        }
    }
}
