import QtQuick
import Vitrum
import Vitrum.Core

// Notepad: a plain text editor with a classic menu bar.
FocusScope {
    id: np
    property var frame: null
    property string path: ""
    property bool dirty: false
    property bool wrap: true
    property bool askPath: false
    readonly property string docName: path.length ? Files.fileName(path) : "Untitled"

    onPathChanged: load()
    Component.onCompleted: { load(); editor.forceActiveFocus() }
    onActiveFocusChanged: if (activeFocus && !askPath) editor.forceActiveFocus()
    onDirtyChanged: updateTitle()
    onDocNameChanged: updateTitle()
    function updateTitle() { if (frame) frame.internalTitle = (dirty ? "*" : "") + docName + " - Notepad" }

    function load() {
        if (path.length && Files.exists(path)) {
            editor.text = Files.readText(path)
            dirty = false
        }
        updateTitle()
    }
    function save() {
        if (!path.length) {
            askPath = true
            savePath.text = Files.documents + "/Untitled.txt"
            savePath.input.forceActiveFocus()
            return
        }
        if (Files.writeText(path, editor.text))
            dirty = false
    }

    Keys.onPressed: (e) => {
        if (!(e.modifiers & Qt.ControlModifier))
            return
        if (e.key === Qt.Key_S) { save(); e.accepted = true }
        else if (e.key === Qt.Key_N) { Shell.openInternal("notepad", {}); e.accepted = true }
        else if (e.key === Qt.Key_W) { frame.close(); e.accepted = true }
    }

    Rectangle {
        id: menuBar
        width: parent.width; height: 22
        gradient: Gradient {
            GradientStop { position: 0; color: "#ffffff" }
            GradientStop { position: 1; color: "#e9eef6" }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#d8dde6" }
        Row {
            x: 2
            height: parent.height
            component MenuTitle: HoverItem {
                id: mtItem
                property string text: ""
                width: mt.implicitWidth + 14; height: parent.height
                radius: 2
                VText { id: mt; anchors.centerIn: parent; text: mtItem.text }
            }
            MenuTitle {
                text: "File"
                onClicked: { const g = mapToItem(Shell.root, 0, height); Shell.showMenu([
                    { text: "New\tCtrl+N", action: () => Shell.openInternal("notepad", {}) },
                    { text: "Save\tCtrl+S", action: () => np.save() },
                    { text: "Save As...", action: () => { np.askPath = true; savePath.text = np.path || Files.documents + "/Untitled.txt"; savePath.input.forceActiveFocus() } },
                    { separator: true },
                    { text: "Exit", action: () => np.frame.close() }
                ], g.x, g.y) }
            }
            MenuTitle {
                text: "Edit"
                onClicked: { const g = mapToItem(Shell.root, 0, height); Shell.showMenu([
                    { text: "Undo\tCtrl+Z", enabled: editor.canUndo, action: () => editor.undo() },
                    { separator: true },
                    { text: "Cut\tCtrl+X", action: () => editor.cut() },
                    { text: "Copy\tCtrl+C", action: () => editor.copy() },
                    { text: "Paste\tCtrl+V", action: () => editor.paste() },
                    { separator: true },
                    { text: "Select All\tCtrl+A", action: () => editor.selectAll() },
                    { text: "Time/Date\tF5", action: () => editor.insert(editor.cursorPosition, Qt.formatDateTime(new Date(), "hh:mm yyyy-MM-dd")) }
                ], g.x, g.y) }
            }
            MenuTitle {
                text: "Format"
                onClicked: { const g = mapToItem(Shell.root, 0, height); Shell.showMenu([
                    { text: "Word Wrap", checked: np.wrap, action: () => np.wrap = !np.wrap }
                ], g.x, g.y) }
            }
        }
    }
    Rectangle {
        id: saveBar
        visible: np.askPath
        y: menuBar.height
        width: parent.width; height: visible ? 32 : 0
        color: "#fff8d8"
        border.color: "#e0cc80"
        Row {
            x: 8; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            VText { text: "Save as:"; anchors.verticalCenter: parent.verticalCenter }
            TextField7 {
                id: savePath
                width: saveBar.width - 220
                onAccepted: { np.path = text; np.askPath = false; Files.writeText(np.path, editor.text); np.dirty = false; editor.forceActiveFocus() }
                Keys.onEscapePressed: { np.askPath = false; editor.forceActiveFocus() }
            }
            Button7 { text: "Save"; onClicked: savePath.accepted() }
            Button7 { text: "Cancel"; onClicked: { np.askPath = false; editor.forceActiveFocus() } }
        }
    }
    Rectangle {
        y: menuBar.height + saveBar.height
        width: parent.width
        height: parent.height - y - status.height
        color: "white"
        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 2
            clip: true
            contentWidth: np.wrap ? width : Math.max(width, editor.contentWidth + 8)
            contentHeight: Math.max(height, editor.contentHeight + 8)
            boundsBehavior: Flickable.StopAtBounds
            function ensureVisible(r) {
                if (contentX >= r.x) contentX = r.x
                else if (contentX + width <= r.x + r.width) contentX = r.x + r.width - width
                if (contentY >= r.y) contentY = r.y
                else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
            }
            TextEdit {
                id: editor
                width: np.wrap ? flick.width - 4 : Math.max(flick.width, contentWidth + 4)
                height: Math.max(flick.height, contentHeight)
                leftPadding: 3
                font.family: "Noto Sans Mono, DejaVu Sans Mono, Monospace"
                font.pixelSize: 13
                wrapMode: np.wrap ? TextEdit.Wrap : TextEdit.NoWrap
                selectByMouse: true
                selectionColor: "#3399ff"
                selectedTextColor: "white"
                focus: true
                onTextChanged: np.dirty = true
                onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)
                Keys.onPressed: (e) => { if (e.key === Qt.Key_F5) { insert(cursorPosition, Qt.formatDateTime(new Date(), "hh:mm yyyy-MM-dd")); e.accepted = true } }
            }
            ScrollIndicator7 { flickable: flick }
        }
    }
    Rectangle {
        id: status
        anchors.bottom: parent.bottom
        width: parent.width; height: 22
        color: Theme.face
        Rectangle { width: parent.width; height: 1; color: "#d7d7d7" }
        VText {
            anchors.right: parent.right; anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: {
                const before = editor.text.substring(0, editor.cursorPosition)
                const ln = before.split("\n").length
                const col = editor.cursorPosition - before.lastIndexOf("\n")
                return "Ln " + ln + ", Col " + col + "    UTF-8"
            }
            color: Theme.textMuted
        }
    }
}
