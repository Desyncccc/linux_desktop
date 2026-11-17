import QtQuick
import Vitrum
import Vitrum.Core

// List row with the soft blue rounded hover/selection highlight.
Item {
    id: hi
    property bool selected: false
    property bool hovered: ma.containsMouse
    property alias mouse: ma
    property bool dark: false
    property int radius: 3
    default property alias content: holder.data
    signal clicked(var mouse)
    signal doubleClicked()
    signal rightClicked(real x, real y)

    Rectangle {
        anchors.fill: parent
        radius: hi.radius
        visible: hi.hovered || hi.selected
        border.color: hi.dark ? Qt.rgba(1, 1, 1, 0.55) : (hi.selected ? Theme.c("#7da2ce") : Theme.c("#b8d6fb"))
        gradient: Gradient {
            GradientStop { position: 0; color: hi.dark ? Qt.rgba(1, 1, 1, 0.30) : (hi.selected ? Theme.c("#dcebfc") : Theme.c("#fafbfd")) }
            GradientStop { position: 1; color: hi.dark ? Qt.rgba(1, 1, 1, 0.12) : (hi.selected ? Theme.c("#c1dcfc") : Theme.c("#ebf3fd")) }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, hi.radius - 1)
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, hi.dark ? 0.25 : 0.6)
        }
    }
    Item {
        id: holder
        anchors.fill: parent
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => {
            if (m.button === Qt.RightButton) {
                const p = mapToItem(Shell.root, m.x, m.y)
                hi.rightClicked(p.x, p.y)
            } else {
                hi.clicked(m)
            }
        }
        onDoubleClicked: (m) => { if (m.button === Qt.LeftButton) hi.doubleClicked() }
    }
}
