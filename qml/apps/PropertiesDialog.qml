import QtQuick
import Vitrum
import Vitrum.Core

FocusScope {
    id: dlg
    property var frame: null
    property string path: ""
    readonly property var info: path.length ? Files.info(path) : ({})
    onInfoChanged: if (frame && info.name) frame.internalTitle = info.name + " Properties"

    Rectangle { anchors.fill: parent; color: Theme.face }
    Rectangle {
        x: 8; y: 8
        width: parent.width - 16
        height: parent.height - 60
        color: "white"
        border.color: "#898c95"
        Column {
            x: 14; y: 14
            width: parent.width - 28
            spacing: 10
            Row {
                spacing: 14
                AppIcon { size: 32; name: Theme.themeIcon(dlg.info.icon || "", "text-x-generic") }
                TextField7 { width: 240; text: dlg.info.name || ""; anchors.verticalCenter: parent.verticalCenter }
            }
            Separator { width: parent.width }
            Grid {
                columns: 2
                columnSpacing: 12
                rowSpacing: 8
                component K: VText { width: 90; color: Theme.textMuted }
                component V: VText { width: 220; wrapMode: Text.WrapAnywhere; maximumLineCount: 3 }
                K { text: "Type:" }
                V { text: dlg.info.type || "" }
                K { text: "Location:" }
                V { text: Files.parentDir(dlg.path) }
                K { text: "Size:" }
                V { text: (dlg.info.size || "") + (dlg.info.files > 0 ? " (" + dlg.info.files + " files)" : "") }
                K { text: "Created:" }
                V { text: dlg.info.created || "" }
                K { text: "Modified:" }
                V { text: dlg.info.modified || "" }
                K { text: "Owner:" }
                V { text: dlg.info.owner || "" }
            }
            Separator { width: parent.width }
            Row {
                spacing: 20
                CheckBox7 { text: "Read-only"; checked: dlg.info.readOnly === true; enabled: false }
                CheckBox7 { text: "Hidden"; checked: dlg.info.hidden === true; enabled: false }
            }
        }
    }
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        spacing: 8
        Button7 { text: "OK"; isDefault: true; onClicked: dlg.frame.close() }
        Button7 { text: "Cancel"; onClicked: dlg.frame.close() }
    }
}
