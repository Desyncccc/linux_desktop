import QtQuick
import Vitrum
import Vitrum.Core

FocusScope {
    id: dlg
    property var frame: null
    property string error: ""
    Component.onCompleted: field.input.forceActiveFocus()
    onActiveFocusChanged: if (activeFocus) field.input.forceActiveFocus()

    function go() {
        const cmd = field.text.trim()
        if (!cmd.length)
            return
        const isPath = cmd.indexOf("/") === 0 || cmd.indexOf("~") === 0
        if (isPath && Files.exists(cmd.replace(/^~/, Files.home))) {
            Shell.openFile(cmd.replace(/^~/, Files.home))
            frame.close()
        } else if (Launcher.runCommand(cmd)) {
            frame.close()
        } else {
            error = "Vitrum cannot find '" + cmd + "'. Make sure you typed the name correctly, and then try again."
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.face }
    Image { x: 14; y: 16; width: 32; height: 32; source: Theme.icon("run"); sourceSize: Qt.size(64, 64) }
    VText {
        x: 58; y: 16
        width: parent.width - 72
        wrapMode: Text.Wrap
        text: dlg.error.length ? dlg.error : "Type the name of a program, folder, document, or Internet resource, and Vitrum will open it for you."
        color: dlg.error.length ? Theme.danger : Theme.text
        maximumLineCount: 3
    }
    VText { x: 14; y: 76; text: "Open:" }
    TextField7 {
        id: field
        x: 58; y: 72
        width: parent.width - 72
        onAccepted: dlg.go()
        Keys.onEscapePressed: dlg.frame.close()
    }
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        spacing: 8
        Button7 { text: "OK"; isDefault: true; onClicked: dlg.go() }
        Button7 { text: "Cancel"; onClicked: dlg.frame.close() }
        Button7 { text: "Browse..."; onClicked: { Shell.openExplorer(Files.home); dlg.frame.close() } }
    }
}
