import QtQuick
import Vitrum
import Vitrum.Core

Item {
    id: cb
    property string text: ""
    property bool checked: false
    signal toggled(bool checked)
    implicitWidth: 18 + label.implicitWidth + 6
    implicitHeight: 20
    opacity: enabled ? 1 : 0.5

    Rectangle {
        id: box
        width: 13; height: 13
        anchors.verticalCenter: parent.verticalCenter
        border.color: ma.containsMouse ? Theme.c("#3c7fb1") : Theme.c("#8e8f8f")
        gradient: Gradient {
            GradientStop { position: 0; color: ma.containsMouse ? Theme.c("#def9fa") : Theme.c("#ebebeb") }
            GradientStop { position: 1; color: ma.containsMouse ? Theme.c("#79c6f9") : Theme.c("#ffffff") }
        }
        VText {
            anchors.centerIn: parent
            visible: cb.checked
            text: "✔"
            font.pixelSize: 11
            color: Theme.c("#4a5f97")
        }
    }
    VText {
        id: label
        x: 19
        anchors.verticalCenter: parent.verticalCenter
        text: cb.text
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: { cb.checked = !cb.checked; cb.toggled(cb.checked) }
    }
}
