import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// Global context menu. Entries: { text, icon, action, enabled, separator, checked, bold }
Item {
    id: menu
    anchors.fill: parent
    visible: Shell.menuOpen
    property var entries: []
    property real px: 0
    property real py: 0

    Connections {
        target: Shell
        function onMenuRequested(entries, x, y) {
            menu.entries = entries
            menu.px = x
            menu.py = y
            Shell.menuOpen = true
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: Shell.menuOpen = false
    }

    RectangularGlow {
        anchors.fill: box
        glowRadius: 5
        spread: 0.1
        cornerRadius: 6
        color: Theme.c("#50000000")
    }
    Rectangle {
        id: box
        width: Math.max(180, col.implicitWidth + 4)
        height: col.implicitHeight + 6
        x: Math.min(menu.px, menu.width - width - 2)
        y: menu.py + height > menu.height ? Math.max(0, menu.py - height) : menu.py
        color: Theme.c("#f0f0f0")
        border.color: Theme.c("#979797")

        Rectangle { // icon gutter
            x: 2; y: 2
            width: 26
            height: parent.height - 4
            color: Theme.c("#f1f1f1")
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.c("#e2e3e3") }
            Rectangle { anchors.right: parent.right; anchors.rightMargin: -1; width: 1; height: parent.height; color: Theme.c("white") }
        }
        Column {
            id: col
            x: 2; y: 3
            width: box.width - 4
            Repeater {
                model: menu.entries
                delegate: Item {
                    id: entry
                    required property var modelData
                    readonly property bool sep: modelData.separator === true
                    readonly property bool on: modelData.enabled !== false
                    width: col.width
                    implicitWidth: label.implicitWidth + 70
                    height: sep ? 7 : 22
                    Separator {
                        visible: entry.sep
                        x: 30; width: parent.width - 32
                        anchors.verticalCenter: parent.verticalCenter
                        dark: Theme.c("#e0e0e0")
                    }
                    Rectangle {
                        visible: !entry.sep && entry.on && ema.containsMouse
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 3
                        border.color: Theme.c("#a8d8eb")
                        gradient: Gradient {
                            GradientStop { position: 0; color: Theme.c("#e8f1fb") }
                            GradientStop { position: 1; color: Theme.c("#d5e7f9") }
                        }
                    }
                    AppIcon {
                        visible: !entry.sep && !!entry.modelData.icon
                        name: entry.modelData.icon || ""
                        size: 16
                        x: 5
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: entry.on ? 1 : 0.4
                    }
                    VText {
                        visible: !entry.sep && entry.modelData.checked === true
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✔"
                    }
                    VText {
                        id: label
                        visible: !entry.sep
                        x: 34
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.modelData.text || ""
                        font.bold: entry.modelData.bold === true
                        color: entry.on ? Theme.text : Theme.textDisabled
                    }
                    MouseArea {
                        id: ema
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !entry.sep && entry.on
                        onClicked: {
                            Shell.menuOpen = false
                            if (entry.modelData.action)
                                entry.modelData.action()
                        }
                    }
                }
            }
        }
    }
}
