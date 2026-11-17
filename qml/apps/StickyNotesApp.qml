import QtQuick
import Vitrum
import Vitrum.Core

// Sticky Notes: one frameless window per note. Notes (text, colour, position
// and size) are kept in ~/.config/Vitrum/stickynotes.json. Opening the app
// without a noteId restores every saved note (the first window spawns the
// others) or starts one empty note.
FocusScope {
    id: note
    property var frame: null
    property string noteId: ""
    property string initialColor: ""     // for notes made with "+"
    property real initialX: -1
    property real initialY: -1
    property string noteColor: "yellow"
    property bool ready: false
    property bool deleted: false
    property alias text: editor.text

    readonly property var palettes: ({
        yellow: { top: "#fefed4", bottom: "#fcf8a8", head: "#f8f3a4", headBottom: "#f1e985", border: "#cfc46a", ink: "#5d5726" },
        blue:   { top: "#e8f6fe", bottom: "#c7e7fb", head: "#c3e3f8", headBottom: "#acd6f2", border: "#86b7d8", ink: "#3b5a70" },
        green:  { top: "#e0f9d9", bottom: "#c2eeb6", head: "#bfe9b2", headBottom: "#a7de98", border: "#8cc27e", ink: "#3f6236" },
        pink:   { top: "#feebf5", bottom: "#f7cbe4", head: "#f4c3df", headBottom: "#ecaccf", border: "#d08fb4", ink: "#6e3c58" },
        purple: { top: "#efebfe", bottom: "#d9d1fb", head: "#d4cbf8", headBottom: "#c2b6f2", border: "#a497d6", ink: "#4b4370" },
        white:  { top: "#ffffff", bottom: "#f3f3f3", head: "#efefef", headBottom: "#e2e2e2", border: "#b9b9b9", ink: "#555555" }
    })
    readonly property var pal: palettes[noteColor] || palettes.yellow

    readonly property string handFont: {
        const families = Qt.fontFamilies()
        const wanted = ["Segoe Print", "Comic Neue", "Kalam", "Patrick Hand", "Architects Daughter", "Indie Flower", "Comic Sans MS"]
        for (const f of wanted)
            if (families.indexOf(f) >= 0)
                return f
        return Theme.font
    }

    // ---- storage
    readonly property string configDir: (Session.env("XDG_CONFIG_HOME") || Files.home + "/.config") + "/Vitrum"
    readonly property string storePath: configDir + "/stickynotes.json"

    function readStore() {
        try {
            const o = JSON.parse(Files.readText(storePath))
            if (o && Array.isArray(o.notes))
                return o
        } catch (e) {
            // missing or unreadable: start afresh
        }
        return { notes: [] }
    }
    function writeStore(o) {
        if (!Files.exists(configDir))
            Files.makeFolder(Files.parentDir(configDir), "Vitrum")
        Files.writeText(storePath, JSON.stringify(o, null, 1))
    }
    function newId() {
        return Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36)
    }
    function save() {
        saveTimer.stop()
        if (!ready || deleted || !frame || noteId === "")
            return
        const store = readStore()
        const rec = { id: noteId, text: editor.text, color: noteColor,
                      x: Math.round(frame.x), y: Math.round(frame.y),
                      w: Math.round(frame.internalWidth), h: Math.round(frame.internalHeight) }
        const i = store.notes.findIndex(n => n.id === noteId)
        if (i >= 0)
            store.notes[i] = rec
        else
            store.notes.push(rec)
        writeStore(store)
    }
    function scheduleSave() {
        if (ready && !deleted)
            saveTimer.restart()
    }
    Timer { id: saveTimer; interval: 400; onTriggered: note.save() }

    // ---- lifecycle
    Component.onCompleted: Qt.callLater(init)   // props arrive after completion

    function init() {
        if (!frame)
            return
        frame.internalTitle = "Sticky Notes"
        frame.internalMinWidth = 150
        frame.internalMinHeight = 110
        const store = readStore()
        if (noteId === "") {
            const others = Shell.windows.filter(w => w !== frame && w.internalKind === "stickynotes" && !w.closing)
            if (others.length > 0) {
                // already running: bring the notes forward instead of adding one
                frame.opacity = 0
                others.forEach(w => Shell.activate(w))
                frame.close()
                return
            }
            if (store.notes.length > 0) {
                const first = store.notes[0]
                noteId = first.id
                restore(first)
                for (let i = 1; i < store.notes.length; i++) {
                    const n = store.notes[i]
                    Shell.openInternal("stickynotes", { noteId: n.id, width: n.w, height: n.h })
                }
            } else {
                noteId = newId()
                ready = true
                save()
            }
        } else {
            const n = store.notes.find(n => n.id === noteId)
            if (n) {
                restore(n)
            } else {
                noteColor = palettes[initialColor] ? initialColor : "yellow"
                if (initialX >= 0)
                    moveTo(initialX, initialY)
                ready = true
                save()
            }
        }
        ready = true
        editor.forceActiveFocus()
    }

    function restore(n) {
        noteColor = palettes[n.color] ? n.color : "yellow"
        editor.text = n.text || ""
        if (n.w > 0 && n.h > 0) {
            frame.internalWidth = Math.max(frame.internalMinWidth, n.w)
            frame.internalHeight = Math.max(frame.internalMinHeight, n.h)
        }
        if (n.x !== undefined && n.y !== undefined)
            moveTo(n.x, n.y)
        editor.cursorPosition = editor.length
    }

    function moveTo(x, y) {
        const a = Shell.workArea
        frame.placed = true
        frame.x = Math.max(a.x, Math.min(x, a.x + a.width - frame.width))
        frame.y = Math.max(a.y, Math.min(y, a.y + a.height - frame.height))
    }

    function newNote() {
        Shell.openInternal("stickynotes", { noteId: newId(), initialColor: noteColor,
                                            initialX: frame.x + 28, initialY: frame.y + 28 })
    }

    function askDelete() {
        const store = readStore()
        if (store.confirmDelete === false || editor.text.length === 0)
            deleteNote()
        else
            Shell.openInternal("stickyconfirm", { note: note })
    }

    function setConfirmDelete(on) {
        const store = readStore()
        store.confirmDelete = on
        writeStore(store)
    }

    function deleteNote() {
        deleted = true
        saveTimer.stop()
        const store = readStore()
        store.notes = store.notes.filter(n => n.id !== noteId)
        writeStore(store)
        frame.close()
    }

    function setColor(c) {
        noteColor = c
        scheduleSave()
    }

    function showMenu(gx, gy) {
        const colours = ["Blue", "Green", "Pink", "Purple", "White", "Yellow"]
        Shell.showMenu([
            { text: "Cut\tCtrl+X", enabled: editor.selectedText.length > 0, action: () => editor.cut() },
            { text: "Copy\tCtrl+C", enabled: editor.selectedText.length > 0, action: () => editor.copy() },
            { text: "Paste\tCtrl+V", enabled: editor.canPaste, action: () => editor.paste() },
            { separator: true },
            { text: "Select All\tCtrl+A", enabled: editor.length > 0, action: () => editor.selectAll() },
            { separator: true }
        ].concat(colours.map(c => ({ text: c, checked: noteColor === c.toLowerCase(),
                                     action: () => note.setColor(c.toLowerCase()) }))), gx, gy)
    }

    Connections {
        target: note.frame
        function onXChanged() { note.scheduleSave() }
        function onYChanged() { note.scheduleSave() }
        function onInternalWidthChanged() { note.scheduleSave() }
        function onInternalHeightChanged() { note.scheduleSave() }
        function onClosingChanged() { if (note.frame.closing && saveTimer.running) note.save() }
    }

    Keys.onPressed: (e) => {
        if (!(e.modifiers & Qt.ControlModifier))
            return
        if (e.key === Qt.Key_N) { newNote(); e.accepted = true }
        else if (e.key === Qt.Key_D) { askDelete(); e.accepted = true }
    }

    // ---- the note
    Rectangle {
        id: paper
        anchors.fill: parent
        border.color: note.pal.border
        gradient: Gradient {
            GradientStop { position: 0; color: note.pal.top }
            GradientStop { position: 1; color: note.pal.bottom }
        }
        Behavior on border.color { ColorAnimation { duration: 150 } }
    }

    Rectangle {
        id: header
        x: 1; y: 1
        width: parent.width - 2
        height: 22
        gradient: Gradient {
            GradientStop { position: 0; color: note.pal.head }
            GradientStop { position: 1; color: note.pal.headBottom }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.45) }

        MouseArea { // drag the note by its header
            id: dragArea
            anchors.fill: parent
            property point pressPos
            property point startPos
            onPressed: (m) => {
                Shell.activate(note.frame)
                pressPos = mapToItem(Shell.root, m.x, m.y)
                startPos = Qt.point(note.frame.x, note.frame.y)
            }
            onPositionChanged: (m) => {
                if (!pressed)
                    return
                const g = mapToItem(Shell.root, m.x, m.y)
                note.frame.x = startPos.x + g.x - pressPos.x
                note.frame.y = Math.max(0, startPos.y + g.y - pressPos.y)
            }
        }

        component HeadButton: Item {
            id: hb
            property string glyph: ""
            property string tip: ""
            property color ink: "#555"
            signal activated()
            width: 22; height: 20
            y: 1
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 2
                visible: hbMa.containsMouse
                color: hbMa.pressed ? Qt.rgba(0, 0, 0, 0.14) : Qt.rgba(1, 1, 1, 0.55)
                border.color: Qt.rgba(0, 0, 0, 0.18)
            }
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -1
                text: hb.glyph
                color: hb.ink
                font.family: Theme.font
                font.pixelSize: 19
            }
            MouseArea {
                id: hbMa
                anchors.fill: parent
                hoverEnabled: true
                onClicked: hb.activated()
            }
        }
        HeadButton {
            x: 2
            glyph: "+"
            ink: note.pal.ink
            onActivated: note.newNote()
        }
        HeadButton {
            anchors.right: parent.right
            anchors.rightMargin: 2
            glyph: "×"
            ink: note.pal.ink
            onActivated: note.askDelete()
        }
    }

    Flickable {
        id: flick
        x: 6
        y: header.height + 4
        width: parent.width - 10
        height: parent.height - y - 14
        clip: true
        contentWidth: width
        contentHeight: Math.max(height, editor.contentHeight + 4)
        boundsBehavior: Flickable.StopAtBounds
        function ensureVisible(r) {
            if (contentY >= r.y)
                contentY = r.y
            else if (contentY + height <= r.y + r.height)
                contentY = r.y + r.height - height
        }
        TextEdit {
            id: editor
            width: flick.width - 6
            height: Math.max(flick.height, contentHeight)
            focus: true
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            persistentSelection: true
            font.family: note.handFont
            font.pixelSize: note.handFont === Theme.font ? 14 : 15
            color: "#1c1c1c"
            selectionColor: "#3399ff"
            selectedTextColor: "white"
            onTextChanged: note.scheduleSave()
            onCursorRectangleChanged: flick.ensureVisible(cursorRectangle)
        }
        ScrollIndicator7 { flickable: flick }
    }
    MouseArea { // context menu on the body
        anchors.fill: flick
        acceptedButtons: Qt.RightButton
        onPressed: (m) => {
            Shell.activate(note.frame)
            const g = mapToItem(Shell.root, m.x, m.y)
            note.showMenu(g.x, g.y)
        }
    }

    // ---- resizing: right and bottom edges, and the corner grip
    component Edge: MouseArea {
        property int edges: 0
        property var win: null
        hoverEnabled: true
        preventStealing: true
        onPressed: (m) => win.beginResize(edges, mapToItem(Shell.root, m.x, m.y))
        onPositionChanged: (m) => { if (pressed) win.updateResize(mapToItem(Shell.root, m.x, m.y)) }
        onReleased: win.endResize()
    }
    Edge { win: note.frame; edges: Qt.RightEdge; cursorShape: Qt.SizeHorCursor; x: parent.width - 4; y: header.height; width: 4; height: parent.height - y - 14 }
    Edge { win: note.frame; edges: Qt.BottomEdge; cursorShape: Qt.SizeVerCursor; x: 0; y: parent.height - 4; width: parent.width - 14; height: 4 }
    Edge {
        win: note.frame
        edges: Qt.RightEdge | Qt.BottomEdge
        cursorShape: Qt.SizeFDiagCursor
        x: parent.width - 14; y: parent.height - 14
        width: 14; height: 14
        Repeater { // dotted grip
            model: [[10, 4], [10, 7], [7, 7], [10, 10], [7, 10], [4, 10]]
            delegate: Rectangle {
                required property var modelData
                x: modelData[0] - 1; y: modelData[1] - 1
                width: 2; height: 2
                color: Qt.rgba(0, 0, 0, 0.28)
            }
        }
    }
}
