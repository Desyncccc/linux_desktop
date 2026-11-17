import QtQuick
import Vitrum
import Vitrum.Core

// Push button with the glossy grey face and blue hover glow.
Item {
    id: btn
    property string text: ""
    property string iconName: ""
    property bool isDefault: false
    property bool flat: false
    property bool checkable: false
    property bool checked: false
    readonly property bool hovered: ma.containsMouse
    readonly property bool pressed: ma.pressed
    signal clicked()

    implicitWidth: Math.max(75, row.implicitWidth + 22)
    implicitHeight: 23
    opacity: enabled ? 1 : 0.55
    activeFocusOnTab: true

    Keys.onReturnPressed: btn.clicked()
    Keys.onSpacePressed: btn.clicked()

    Rectangle {
        anchors.fill: parent
        radius: 3
        visible: !btn.flat || btn.hovered || btn.checked
        border.color: Theme.c(btn.pressed || btn.checked ? "#2c628b" : btn.hovered ? "#3c7fb1" : (btn.isDefault || btn.activeFocus ? "#3399ff" : "#707070"))
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.c(btn.pressed || btn.checked ? "#e5f4fc" : btn.hovered ? "#eaf6fd" : "#f2f2f2") }
            GradientStop { position: 0.49; color: Theme.c(btn.pressed || btn.checked ? "#c4e5f6" : btn.hovered ? "#d9f0fc" : "#ebebeb") }
            GradientStop { position: 0.5; color: Theme.c(btn.pressed || btn.checked ? "#98d1ef" : btn.hovered ? "#bee6fd" : "#dddddd") }
            GradientStop { position: 1.0; color: Theme.c(btn.pressed || btn.checked ? "#68b3db" : btn.hovered ? "#a7d9f5" : "#cfcfcf") }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 2
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, btn.pressed ? 0.2 : 0.7)
        }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        AppIcon {
            visible: btn.iconName.length > 0
            name: btn.iconName
            size: 16
            anchors.verticalCenter: parent.verticalCenter
        }
        VText {
            text: btn.text
            visible: text.length > 0
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (btn.checkable)
                btn.checked = !btn.checked
            btn.clicked()
        }
    }
}
