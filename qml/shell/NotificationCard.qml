import QtQuick
import Vitrum
import Vitrum.Core

// A notification: used both for toasts and in the Action Center.
Item {
    id: card
    property int notificationId: 0
    property string appName: ""
    property string appIcon: ""
    property string summary: ""
    property string body: ""
    property var actions: []
    property string image: ""
    property var time: null
    property bool toast: false
    signal dismissed()
    signal actionClicked(string key)
    signal clicked()

    height: Math.max(66, col.implicitHeight + 20)

    Rectangle {
        anchors.fill: parent
        radius: 4
        color: card.toast ? "transparent" : Qt.rgba(1, 1, 1, cardMouse.containsMouse ? 0.20 : 0.13)
        border.color: card.toast ? "transparent" : Qt.rgba(1, 1, 1, 0.25)
    }
    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (card.actions && card.actions.length > 0) {
                const def = card.actions.find(a => a.key === "default")
                card.actionClicked(def ? def.key : card.actions[0].key)
            } else {
                card.clicked()
            }
        }
    }
    AppIcon {
        x: 10; y: 12
        size: 32
        name: card.image.length > 0 ? card.image : card.appIcon.length > 0 ? card.appIcon : Theme.icon("vitrum")
        fallback: "dialog-information"
    }
    Column {
        id: col
        x: 52; y: 10
        width: parent.width - 52 - 30
        spacing: 2
        Text {
            width: parent.width
            text: card.summary
            color: "white"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
            elide: Text.ElideRight
            renderType: Text.NativeRendering
        }
        Text {
            width: parent.width
            text: card.body
            visible: text.length > 0
            color: Qt.rgba(1, 1, 1, 0.88)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            textFormat: Text.StyledText
            renderType: Text.NativeRendering
        }
        Text {
            text: (card.appName || "") + (card.time ? "  ·  " + Qt.formatTime(card.time, Prefs.clock24h ? "HH:mm" : "h:mm AP") : "")
            color: Qt.rgba(1, 1, 1, 0.6)
            font.family: Theme.font
            font.pixelSize: Theme.fontSizeSmall
            renderType: Text.NativeRendering
        }
        Row {
            spacing: 6
            visible: card.actions && card.actions.filter(a => a.key !== "default").length > 0
            topPadding: 4
            Repeater {
                model: card.actions ? card.actions.filter(a => a.key !== "default") : []
                Button7 {
                    required property var modelData
                    text: modelData.label
                    onClicked: card.actionClicked(modelData.key)
                }
            }
        }
    }
    Item {
        anchors.right: parent.right
        width: 28; height: 28
        visible: cardMouse.containsMouse || xMouse.containsMouse
        Image { anchors.centerIn: parent; width: 12; height: 12; sourceSize: Qt.size(24, 24); source: Theme.icon("close"); opacity: xMouse.containsMouse ? 1 : 0.7 }
        MouseArea { id: xMouse; anchors.fill: parent; hoverEnabled: true; onClicked: card.dismissed() }
    }
}
