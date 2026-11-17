import QtQuick
import Vitrum
import Vitrum.Core

// "Delete this note?" confirmation for Sticky Notes.
FocusScope {
    id: dlg
    property var frame: null
    property var note: null     // the StickyNotesApp asking

    Component.onCompleted: Qt.callLater(place)
    onActiveFocusChanged: if (activeFocus) yes.forceActiveFocus()

    function place() {
        if (!frame || !note || !note.frame)
            return
        const n = note.frame
        const a = Shell.workArea
        frame.placed = true
        frame.x = Math.max(a.x, Math.min(n.x + (n.width - frame.width) / 2, a.x + a.width - frame.width))
        frame.y = Math.max(a.y, Math.min(n.y + (n.height - frame.height) / 2, a.y + a.height - frame.height))
        yes.forceActiveFocus()
    }
    function answer(remove) {
        if (remove && note) {
            if (dontAsk.checked)
                note.setConfirmDelete(false)
            note.deleteNote()
        }
        frame.close()
    }

    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Escape || e.key === Qt.Key_N) { answer(false); e.accepted = true }
        else if (e.key === Qt.Key_Y) { answer(true); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { answer(!no.activeFocus); e.accepted = true }
    }

    Rectangle { anchors.fill: parent; color: Theme.c("white") }
    Image {
        x: 16; y: 18
        width: 32; height: 32
        sourceSize: Qt.size(64, 64)
        source: Theme.icon("warning")
    }
    VText {
        x: 60; y: 24
        width: parent.width - 76
        wrapMode: Text.Wrap
        text: "Are you sure you want to delete this note?"
        color: Theme.c("#003399")
        font.pixelSize: Theme.fontSizeLarge - 1
    }
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width; height: 44
        color: Theme.face
        Rectangle { width: parent.width; height: 1; color: Theme.c("#dfdfdf") }
        CheckBox7 {
            id: dontAsk
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "Don't display this message again"
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Button7 { id: yes; text: "Yes"; isDefault: true; implicitWidth: 66; onClicked: dlg.answer(true) }
            Button7 { id: no; text: "No"; implicitWidth: 66; onClicked: dlg.answer(false) }
        }
    }
}
