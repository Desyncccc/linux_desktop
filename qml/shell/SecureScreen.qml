import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// Ctrl+Alt+Del options screen.
FocusScope {
    id: ss
    anchors.fill: parent
    visible: Shell.secureScreen
    onVisibleChanged: if (visible) ss.forceActiveFocus()
    Keys.onEscapePressed: Shell.secureScreen = false

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.darker(Theme.accent, 2.4) }
            GradientStop { position: 0.6; color: Qt.darker(Theme.accent, 1.5) }
            GradientStop { position: 1; color: Qt.darker(Theme.accent, 2.0) }
        }
    }
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    Column {
        anchors.centerIn: parent
        spacing: 6
        component Choice: Item {
            id: ch
            property string text: ""
            signal activated()
            width: 300; height: 36
            Rectangle {
                anchors.fill: parent
                radius: 3
                visible: chMouse.containsMouse
                color: Qt.rgba(1, 1, 1, 0.15)
                border.color: Qt.rgba(1, 1, 1, 0.4)
            }
            Text {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                text: ch.text
                color: "white"
                font.family: Theme.font
                font.pixelSize: 17
            }
            MouseArea { id: chMouse; anchors.fill: parent; hoverEnabled: true; onClicked: { Shell.secureScreen = false; ch.activated() } }
        }
        Choice { text: "Lock"; onActivated: Shell.lock() }
        Choice { text: "Sign out"; onActivated: Shell.logout() }
        Choice { text: "Change a password"; onActivated: Launcher.run([Launcher.terminal, "-e", "passwd"]) }
        Choice { text: "Task Manager"; onActivated: Shell.openTaskManager() }
        Item { width: 1; height: 24 }
        Button7 {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Cancel"
            onClicked: Shell.secureScreen = false
        }
    }
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 30
        width: 36; height: 30
        radius: 4
        border.color: Qt.rgba(0, 0, 0, 0.6)
        gradient: Gradient {
            GradientStop { position: 0; color: sMouse.containsMouse ? "#f7b8a8" : Qt.rgba(1, 1, 1, 0.3) }
            GradientStop { position: 1; color: sMouse.containsMouse ? "#c43b22" : Qt.rgba(1, 1, 1, 0.08) }
        }
        Image { anchors.centerIn: parent; width: 16; height: 16; sourceSize: Qt.size(32, 32); source: Theme.icon("power") }
        MouseArea { id: sMouse; anchors.fill: parent; hoverEnabled: true; onClicked: Sys.powerOff() }
    }
}
