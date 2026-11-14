import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// Panel that pops up above the taskbar. `glass: false` gives the light
// "white panel" treatment used by the clock and volume flyouts.
Item {
    id: fly
    property bool open: false
    property bool glass: false
    property real anchorX: 0
    default property alias content: inner.data
    property real slide: open ? 0 : 12

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.anim(140) } }
    Behavior on slide { NumberAnimation { duration: Theme.anim(160); easing.type: Easing.OutCubic } }

    x: Math.max(4, Math.min(anchorX - width / 2, Shell.screenWidth - width - 4))
    y: Shell.screenHeight - Theme.taskbarHeight - height - 6 + slide

    // Swallow clicks so they don't reach the dismiss layer underneath.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: (m) => m.accepted = true }

    RectangularGlow {
        anchors.fill: parent
        glowRadius: 10
        spread: 0.15
        cornerRadius: 14
        color: "#70000000"
    }
    GlassPanel {
        anchors.fill: parent
        tracking: fly
        radius: 6
    }
    Rectangle {
        visible: !fly.glass
        anchors.fill: parent
        anchors.margins: 1
        radius: 5
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.96) }
            GradientStop { position: 1; color: Qt.rgba(0.94, 0.96, 0.98, 0.96) }
        }
    }
    Item {
        id: inner
        anchors.fill: parent
    }
}
