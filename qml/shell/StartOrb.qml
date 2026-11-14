import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// The round glass start button.
Item {
    id: orb
    property bool open: Shell.startOpen
    readonly property bool hovered: ma.containsMouse
    width: Theme.isModern ? 48 : Theme.taskbarHeight + 14
    height: Theme.taskbarHeight

    readonly property real d: Math.min(height - 4, 36)

    Rectangle {
        visible: Theme.isModern
        anchors.centerIn: parent
        width: 40; height: 38
        radius: 5
        color: Qt.rgba(1, 1, 1, ma.pressed ? 0.05 : (orb.hovered || orb.open) ? 0.10 : 0)
        Image {
            anchors.centerIn: parent
            width: 24; height: 24
            sourceSize: Qt.size(48, 48)
            source: Theme.icon("vitrum")
        }
    }
    RectangularGlow {
        visible: !Theme.isModern
        anchors.centerIn: sphere
        width: sphere.width - 8; height: sphere.height - 8
        glowRadius: orb.hovered || orb.open ? 10 : 4
        spread: 0.2
        cornerRadius: width / 2 + glowRadius
        color: orb.hovered || orb.open ? Qt.rgba(0.55, 0.85, 1, 0.75) : Qt.rgba(0.3, 0.6, 1, 0.35)
        Behavior on glowRadius { NumberAnimation { duration: Theme.anim(150) } }
    }
    Rectangle {
        id: sphere
        visible: !Theme.isModern
        anchors.centerIn: parent
        width: orb.d; height: orb.d
        radius: width / 2
        border.color: Qt.rgba(0, 0, 0, 0.7)
        gradient: Gradient {
            GradientStop { position: 0.0; color: orb.open ? "#2a5a8c" : Qt.lighter(Theme.accent, orb.hovered ? 1.55 : 1.3) }
            GradientStop { position: 0.5; color: orb.open ? "#123d6b" : Qt.darker(Theme.accent, orb.hovered ? 1.05 : 1.35) }
            GradientStop { position: 1.0; color: orb.open ? "#2b79c2" : Qt.lighter(Theme.accent, orb.hovered ? 1.4 : 1.05) }
        }
        Rectangle { // inner rim
            anchors.fill: parent; anchors.margins: 1
            radius: width / 2
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, 0.45)
        }
        Rectangle { // gloss cap
            x: parent.width * 0.14; y: 2
            width: parent.width * 0.72; height: parent.height * 0.46
            radius: height / 2
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.75) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.05) }
            }
        }
        Image {
            anchors.centerIn: parent
            width: parent.width * 0.52; height: width
            sourceSize: Qt.size(width * 2, height * 2)
            source: Theme.icon("vitrum-mono")
            opacity: 0.95
        }
        Rectangle { // bottom reflected light
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height * 0.70
            width: parent.width * 0.55; height: parent.height * 0.22
            radius: height / 2
            color: Qt.rgba(0.7, 0.95, 1, orb.hovered ? 0.45 : 0.25)
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: (m) => {
            if (m.button === Qt.RightButton) {
                const g = mapToItem(Shell.root, 0, 0)
                Shell.showQuickLinks(g.x, g.y)
            } else {
                Shell.toggleStart()
            }
        }
    }
}
