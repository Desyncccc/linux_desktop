import QtQuick
import Qt.labs.folderlistmodel
import Vitrum
import Vitrum.Core

// Icons on the desktop: system places followed by ~/Desktop contents,
// arranged in columns from the top-left, with marquee selection.
FocusScope {
    id: desk
    readonly property int cellW: 82
    readonly property int cellH: 90
    readonly property int rows: Math.max(1, Math.floor((height - 8) / cellH))
    property var selected: ({})
    property string renaming: ""

    FolderListModel {
        id: folder
        folder: Files.toUrl(Files.desktop)
        showDirsFirst: true
        showHidden: false
        sortField: FolderListModel.Name
    }
    property int trashRevision: 0
    Connections { target: Files; function onChanged(dir) { desk.trashRevision++ } }

    readonly property var items: {
        const list = [
            { key: "::computer", name: "Computer", icon: Theme.icon("computer"), kind: "computer" },
            { key: "::home", name: Sys.realName || "Home", icon: Theme.icon("user-home"), kind: "home" },
            { key: "::trash", name: "Recycle Bin", icon: (trashRevision, Files.trashCount() > 0) ? Theme.icon("trash-full") : Theme.icon("trash-empty"), kind: "trash" }
        ]
        if (folder.status === FolderListModel.Ready) {
            for (let i = 0; i < folder.count; ++i) {
                const path = folder.get(i, "filePath")
                const isDir = folder.get(i, "fileIsDir")
                list.push({ key: path, name: Files.displayName(path), path: path, kind: isDir ? "dir" : "file",
                            icon: isDir ? Theme.icon("folder")
                                        : (Files.isImage(path) ? "file://" + path : Theme.themeIcon(Files.iconName(path), "text-x-generic")) })
            }
        }
        return list
    }

    function open(item) {
        switch (item.kind) {
        case "computer": Shell.openExplorer("::computer"); break
        case "home": Shell.openExplorer(Files.home); break
        case "trash": Shell.openExplorer(Files.trash); break
        case "dir": Shell.openExplorer(item.path); break
        default: Shell.openFile(item.path)
        }
    }

    function selectOnly(key) {
        const s = {}
        if (key)
            s[key] = true
        selected = s
    }

    function selectedPaths() {
        return items.filter(it => selected[it.key] && it.path).map(it => it.path)
    }

    function iconMenu(item, gx, gy) {
        if (!selected[item.key])
            selectOnly(item.key)
        const entries = [{ text: "Open", bold: true, action: () => desk.open(item) }]
        if (item.kind === "trash") {
            entries.push({ text: "Empty Recycle Bin", enabled: Files.trashCount() > 0, action: () => Files.emptyTrash() })
        } else if (item.path) {
            if (Apps.isProgramFile(item.path)) {
                entries.push({ text: "Pin to taskbar", icon: Theme.icon("pin"), action: () => { const id = Apps.ensureEntryForFile(item.path); if (id) Prefs.pin(id) } })
                entries.push({ text: "Pin to Start menu", action: () => { const id = Apps.ensureEntryForFile(item.path); if (id) Prefs.pinToStart(id) } })
            }
            entries.push({ separator: true })
            entries.push({ text: "Cut", action: () => Files.cut(desk.selectedPaths()) })
            entries.push({ text: "Copy", action: () => Files.copy(desk.selectedPaths()) })
            entries.push({ separator: true })
            entries.push({ text: "Delete", action: () => Files.moveToTrash(desk.selectedPaths()) })
            entries.push({ text: "Rename", action: () => desk.renaming = item.key })
        }
        entries.push({ separator: true })
        entries.push({ text: "Properties", action: () => {
            if (item.kind === "computer") Shell.openAbout()
            else Shell.openProperties(item.path || (item.kind === "home" ? Files.home : Files.trash))
        } })
        Shell.showMenu(entries, gx, gy)
    }

    function desktopMenu(gx, gy) {
        Shell.showMenu([
            { text: "Refresh", action: () => { Apps.reload(); desk.trashRevision++ } },
            { text: "Paste", enabled: Files.clipboard.length > 0, action: () => Files.paste(Files.desktop) },
            { separator: true },
            { text: "New folder", icon: Theme.icon("folder"), action: () => { const p = Files.makeFolder(Files.desktop); if (p) { desk.selectOnly(p); desk.renaming = p } } },
            { text: "New text document", icon: "text-x-generic", action: () => { const p = Files.makeFile(Files.desktop); if (p) { desk.selectOnly(p); desk.renaming = p } } },
            { separator: true },
            { text: "Open terminal here", icon: Theme.icon("terminal"), action: () => Launcher.openTerminal(Files.desktop) },
            { separator: true },
            { text: "Display settings", icon: Theme.icon("settings"), action: () => Shell.openSettings("display") },
            { text: "Personalize", icon: Theme.icon("settings"), action: () => Shell.openSettings("personalize") }
        ], gx, gy)
    }

    // Background: deselect, marquee, context menu
    MouseArea {
        id: bg
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property point origin
        property bool marquee: false
        onPressed: (m) => {
            Shell.deactivate()
            desk.forceActiveFocus()
            desk.renaming = ""
            if (m.button === Qt.RightButton) {
                desk.selectOnly("")
                const g = mapToItem(Shell.root, m.x, m.y)
                desk.desktopMenu(g.x, g.y)
                return
            }
            if (!(m.modifiers & Qt.ControlModifier))
                desk.selectOnly("")
            origin = Qt.point(m.x, m.y)
            marquee = true
            band.x = m.x; band.y = m.y; band.width = 0; band.height = 0
        }
        onPositionChanged: (m) => {
            if (!marquee)
                return
            band.x = Math.min(origin.x, m.x)
            band.y = Math.min(origin.y, m.y)
            band.width = Math.abs(m.x - origin.x)
            band.height = Math.abs(m.y - origin.y)
            const s = {}
            for (let i = 0; i < desk.items.length; ++i) {
                const cx = 4 + Math.floor(i / desk.rows) * desk.cellW, cy = 4 + (i % desk.rows) * desk.cellH
                if (cx < band.x + band.width && cx + desk.cellW > band.x && cy < band.y + band.height && cy + desk.cellH > band.y)
                    s[desk.items[i].key] = true
            }
            desk.selected = s
        }
        onReleased: marquee = false
    }

    Repeater {
        model: desk.items
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool sel: desk.selected[modelData.key] === true
            x: 4 + Math.floor(index / desk.rows) * desk.cellW
            y: 4 + (index % desk.rows) * desk.cellH
            width: desk.cellW - 4
            height: desk.cellH - 4

            Rectangle {
                anchors.fill: parent
                radius: 3
                visible: cell.sel || cellMouse.containsMouse
                color: cell.sel ? Qt.rgba(0.6, 0.8, 1, 0.38) : Qt.rgba(0.7, 0.85, 1, 0.20)
                border.color: cell.sel ? Qt.rgba(0.75, 0.9, 1, 0.85) : Qt.rgba(0.8, 0.92, 1, 0.5)
            }
            AppIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 5
                size: 48
                name: cell.modelData.icon
                fallback: "text-x-generic"
            }
            Text {
                visible: desk.renaming !== cell.modelData.key
                x: 2; y: 56
                width: parent.width - 4
                horizontalAlignment: Text.AlignHCenter
                text: cell.modelData.name
                color: "white"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                wrapMode: Text.Wrap
                maximumLineCount: cell.sel ? 4 : 2
                elide: Text.ElideRight
                style: Text.Raised
                styleColor: "#c0000000"
                renderType: Text.NativeRendering
            }
            MouseArea {
                id: cellMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: (m) => {
                    Shell.deactivate()
                    desk.forceActiveFocus()
                    if (m.modifiers & Qt.ControlModifier) {
                        const s = Object.assign({}, desk.selected)
                        s[cell.modelData.key] = !s[cell.modelData.key]
                        desk.selected = s
                    } else if (!cell.sel) {
                        desk.selectOnly(cell.modelData.key)
                    }
                    if (m.button === Qt.RightButton) {
                        const g = mapToItem(Shell.root, m.x, m.y)
                        desk.iconMenu(cell.modelData, g.x, g.y)
                    }
                }
                onDoubleClicked: (m) => { if (m.button === Qt.LeftButton) desk.open(cell.modelData) }
            }
            TextField7 {
                visible: desk.renaming === cell.modelData.key
                x: -6; y: 56
                width: parent.width + 12
                height: 22
                onVisibleChanged: if (visible) { text = cell.modelData.name; input.forceActiveFocus(); input.selectAll() }
                onAccepted: {
                    if (cell.modelData.path && text !== cell.modelData.name)
                        Files.rename(cell.modelData.path, text)
                    desk.renaming = ""
                }
                Keys.onEscapePressed: desk.renaming = ""
            }
        }
    }

    Rectangle {
        id: band
        visible: bg.marquee && width > 2
        color: Qt.rgba(0.2, 0.55, 1, 0.25)
        border.color: Qt.rgba(0.5, 0.75, 1, 0.9)
    }

    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Delete) {
            Files.moveToTrash(desk.selectedPaths())
            e.accepted = true
        } else if (e.key === Qt.Key_F2) {
            const p = desk.selectedPaths()
            if (p.length === 1)
                desk.renaming = p[0]
            e.accepted = true
        } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
            desk.items.filter(it => desk.selected[it.key]).forEach(it => desk.open(it))
            e.accepted = true
        } else if (e.key === Qt.Key_A && (e.modifiers & Qt.ControlModifier)) {
            const s = {}
            desk.items.forEach(it => s[it.key] = true)
            desk.selected = s
            e.accepted = true
        } else if (e.key === Qt.Key_F5) {
            desk.trashRevision++
            e.accepted = true
        }
    }
}
