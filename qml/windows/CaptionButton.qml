import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// Minimize / maximize / close button hanging from the top edge of the frame.
Item {
    id: cap
    property string kind: "close"   // "minimize" | "maximize" | "restore" | "close"
    property bool active: true
    property bool first: false
    property bool last: false
    property bool lastInRow: false
    readonly property bool hovered: ma.containsMouse
    readonly property alias pressed: ma.pressed
    signal clicked()
    signal hoverHeld()

    readonly property bool isClose: kind === "close"
    readonly property color baseTop: isClose ? (active ? "#e8a597" : "#dcc4bf")
                                    : Theme.isBasic ? (active ? "#eef3fa" : "#f2f4f7") : Qt.rgba(1, 1, 1, active ? 0.45 : 0.35)
    readonly property color baseBottom: isClose ? (active ? "#c44a38" : "#c9a7a0")
                                       : Theme.isBasic ? (active ? "#bccde6" : "#d8dee7") : Qt.rgba(1, 1, 1, active ? 0.12 : 0.10)
    readonly property color hotTop: isClose ? "#f7b8a8" : "#c3e4fb"
    readonly property color hotBottom: isClose ? "#d92e15" : "#3b8de0"

    // Modern: flat full-height buttons
    Rectangle {
        anchors.fill: parent
        visible: Theme.isModern
        radius: cap.isClose && cap.lastInRow ? Theme.frameRadius - 1 : 0
        color: cap.isClose ? (cap.pressed ? "#a8241a" : cap.hovered ? "#c42b1c" : "transparent")
                           : (cap.pressed ? Qt.rgba(0, 0, 0, 0.14) : cap.hovered ? Qt.rgba(0, 0, 0, 0.07) : "transparent")
        Rectangle { // square off the corners that aren't the window corner
            visible: parent.radius > 0
            width: parent.width; height: parent.radius
            anchors.bottom: parent.bottom
            color: parent.color
        }
        Rectangle {
            visible: parent.radius > 0
            width: parent.radius; height: parent.height
            color: parent.color
        }
    }
    Item {
        anchors.centerIn: parent
        width: 10; height: 10
        visible: Theme.isModern
        readonly property color ink: cap.isClose && cap.hovered ? "white" : (cap.active ? "#1a1a1a" : "#8a8a8a")
        Rectangle { visible: cap.kind === "minimize"; y: 5; width: 10; height: 1; color: parent.ink }
        Rectangle { visible: cap.kind === "maximize"; anchors.fill: parent; color: "transparent"; border.color: parent.ink; radius: 1 }
        Item {
            visible: cap.kind === "restore"
            anchors.fill: parent
            Rectangle { x: 2; y: 0; width: 8; height: 8; color: "transparent"; border.color: parent.parent.ink; radius: 1 }
            Rectangle { x: 0; y: 2; width: 8; height: 8; color: cap.isClose ? "transparent" : "#f3f3f3"; border.color: parent.parent.ink; radius: 1 }
        }
        Repeater {
            model: cap.isClose ? [45, -45] : []
            Rectangle {
                required property var modelData
                anchors.centerIn: parent
                width: 13; height: 1.2
                rotation: modelData
                antialiasing: true
                color: parent.ink
            }
        }
    }

    RectangularGlow {
        visible: cap.hovered && Theme.isAero
        anchors.fill: face
        glowRadius: 6
        spread: 0.2
        cornerRadius: 6
        color: cap.isClose ? "#c0ff4a20" : "#a05fc4ff"
    }
    Rectangle {
        id: face
        visible: !Theme.isModern
        anchors.fill: parent
        radius: 4
        // Only the outer bottom corners are rounded; square off the rest.
        border.color: Qt.rgba(0, 0, 0, 0.55)
        gradient: Gradient {
            GradientStop { position: 0.0; color: cap.pressed ? Qt.darker(cap.hotTop, 1.2) : cap.hovered ? cap.hotTop : cap.baseTop }
            GradientStop { position: 0.5; color: cap.pressed ? Qt.darker(cap.hotBottom, 1.25) : cap.hovered ? Qt.lighter(cap.hotBottom, 1.15) : Qt.tint(cap.baseBottom, Qt.rgba(1, 1, 1, 0.05)) }
            GradientStop { position: 1.0; color: cap.pressed ? Qt.darker(cap.hotBottom, 1.3) : cap.hovered ? cap.hotBottom : cap.baseBottom }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 3
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, cap.hovered ? 0.6 : 0.4)
        }
    }
    // Glyphs (white with a dark outline).
    Item {
        visible: !Theme.isModern
        anchors.centerIn: parent
        width: 14; height: 12
        // minimize
        Rectangle {
            visible: cap.kind === "minimize"
            x: 2; y: 8; width: 10; height: 3
            color: "white"; border.color: "#4a4a4a"; border.width: 0.8
        }
        // maximize
        Rectangle {
            visible: cap.kind === "maximize"
            x: 1.5; y: 1; width: 11; height: 9
            color: "transparent"; border.color: "#3a3a3a"; border.width: 1
            Rectangle { x: 1; y: 1; width: parent.width - 2; height: parent.height - 2; color: "transparent"; border.color: "white"; border.width: 2 }
        }
        // restore
        Item {
            visible: cap.kind === "restore"
            anchors.fill: parent
            Rectangle { x: 4; y: 0; width: 9; height: 7; color: "transparent"; border.color: "white"; border.width: 1.5
                Rectangle { anchors.fill: parent; anchors.margins: -0.8; color: "transparent"; border.color: "#3a3a3a"; border.width: 0.6 } }
            Rectangle { x: 1; y: 4; width: 9; height: 7; color: "#40000000"; border.color: "white"; border.width: 1.5
                Rectangle { anchors.fill: parent; anchors.margins: -0.8; color: "transparent"; border.color: "#3a3a3a"; border.width: 0.6 } }
        }
        // close
        Item {
            visible: cap.isClose
            anchors.fill: parent
            Repeater {
                model: [45, -45]
                Rectangle {
                    required property var modelData
                    anchors.centerIn: parent
                    width: 13; height: 3
                    radius: 1
                    rotation: modelData
                    color: "white"
                    border.color: "#5a2a22"
                    border.width: 0.7
                    antialiasing: true
                }
            }
        }
    }
    Timer {
        interval: 650
        running: cap.hovered && !cap.pressed
        onTriggered: cap.hoverHeld()
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: cap.clicked()
    }
}
