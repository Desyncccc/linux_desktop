import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

Flyout {
    id: fly
    open: Shell.flyout === "volume"
    anchorX: Shell.flyoutX
    width: 92
    height: 270

    VText {
        x: 0; y: 10; width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "Speakers"
        color: Theme.link
    }
    Slider7 {
        x: (parent.width - width) / 2
        y: 34
        vertical: true
        height: 170
        from: 0; to: 100
        value: Sys.volume
        enabled: Sys.hasAudio
        onMoved: (v) => Sys.setVolume(v)
    }
    VText {
        x: 0; y: 208; width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: Sys.hasAudio ? Sys.volume + "%" : "No device"
        color: Theme.textMuted
    }
    HoverItem {
        x: (parent.width - 34) / 2; y: 228
        width: 34; height: 30
        enabled: Sys.hasAudio
        Image {
            anchors.centerIn: parent
            width: 20; height: 20
            source: Theme.icon(Sys.muted ? "volume-muted" : "volume")
            sourceSize: Qt.size(40, 40)
            layer.enabled: true
            layer.effect: ColorOverlay { color: Theme.c("#1e4f8f") }
        }
        onClicked: Sys.toggleMute()
    }
}
