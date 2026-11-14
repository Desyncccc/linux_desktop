import QtQuick
import Vitrum
import Vitrum.Core

// Glass outline showing where a dragged window will snap.
Item {
    id: prev
    property rect target: Shell.snapRect
    readonly property bool shown: Shell.snapTarget !== ""
    x: target.x + 6
    y: target.y + 6
    width: Math.max(0, target.width - 12)
    height: Math.max(0, target.height - 12)
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: Theme.anim(140) } }
    Behavior on x { enabled: prev.shown; NumberAnimation { duration: Theme.anim(140) } }
    Behavior on y { enabled: prev.shown; NumberAnimation { duration: Theme.anim(140) } }
    Behavior on width { enabled: prev.shown; NumberAnimation { duration: Theme.anim(140) } }
    Behavior on height { enabled: prev.shown; NumberAnimation { duration: Theme.anim(140) } }

    GlassPanel {
        anchors.fill: parent
        tracking: prev
        radius: 6
        intensity: Theme.glassIntensity(true) * 0.7
        brightness: 0.12
    }
    Rectangle {
        anchors.fill: parent
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.10)
        border.color: Qt.rgba(1, 1, 1, 0.8)
    }
}
