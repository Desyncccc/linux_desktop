import QtQuick
import Vitrum
import Vitrum.Core

FocusScope {
    id: tf
    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    property bool italicPlaceholder: true
    property string iconName: ""
    property bool rounded: false
    property alias echoMode: input.echoMode
    signal accepted()
    implicitWidth: 200
    implicitHeight: 23

    Rectangle {
        anchors.fill: parent
        radius: tf.rounded ? 3 : 0
        color: Theme.c("white")
        border.color: Theme.c(input.activeFocus ? "#3d7bad" : (ma.containsMouse ? "#5794bf" : "#abadb3"))
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: tf.rounded ? 2 : 0
            color: "transparent"
            border.color: input.activeFocus ? Theme.c("#a4c9e3") : "transparent"
        }
    }
    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: tf.iconName ? 26 : 6
        verticalAlignment: TextInput.AlignVCenter
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        color: Theme.text
        selectionColor: Theme.c("#3399ff")
        selectedTextColor: Theme.c("white")
        clip: true
        focus: true
        selectByMouse: true
        onAccepted: tf.accepted()
    }
    VText {
        anchors.fill: input
        verticalAlignment: Text.AlignVCenter
        text: tf.placeholder
        font.italic: tf.italicPlaceholder
        color: Theme.c("#7a7a7a")
        visible: input.text.length === 0
    }
    AppIcon {
        visible: tf.iconName.length > 0
        name: tf.iconName
        size: 16
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        opacity: 0.8
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.IBeamCursor
    }
}
