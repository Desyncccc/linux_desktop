import QtQuick
import Vitrum
import Vitrum.Core

// Drop-down list box. `model` is an array of strings; picks via the shell menu.
Item {
    id: combo
    property var model: []
    property int currentIndex: 0
    readonly property string currentText: currentIndex >= 0 && currentIndex < model.length ? model[currentIndex] : ""
    property string displayText: currentText
    signal activated(int index)
    implicitWidth: 150
    implicitHeight: 22
    opacity: enabled ? 1 : 0.5

    Rectangle {
        anchors.fill: parent
        radius: 2
        border.color: ma.containsMouse ? "#3c7fb1" : "#8e8f8f"
        gradient: Gradient {
            GradientStop { position: 0; color: ma.containsMouse ? "#eaf6fd" : "#f6f6f6" }
            GradientStop { position: 0.5; color: ma.containsMouse ? "#d9f0fc" : "#e9e9e9" }
            GradientStop { position: 0.51; color: ma.containsMouse ? "#bee6fd" : "#dddddd" }
            GradientStop { position: 1; color: ma.containsMouse ? "#a7d9f5" : "#d3d3d3" }
        }
    }
    VText {
        x: 6
        width: parent.width - 24
        anchors.verticalCenter: parent.verticalCenter
        text: combo.displayText
    }
    VText {
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: "▾"
        font.pixelSize: 10
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            const p = combo.mapToItem(Shell.root, 0, combo.height)
            const entries = []
            for (let i = 0; i < combo.model.length; ++i) {
                const idx = i
                entries.push({ text: combo.model[i], checked: i === combo.currentIndex,
                               action: () => { combo.currentIndex = idx; combo.activated(idx) } })
            }
            Shell.showMenu(entries, p.x, p.y)
        }
    }
}
