import QtQuick
import Vitrum
import Vitrum.Core

// Windows Explorer, laid out the way glass-era users know it:
//   glass travel band (back/forward + recent pages, breadcrumb address bar
//   with per-level folder menus, refresh, search box), optional menu bar,
//   command bar (Organize, contextual commands, view picker, preview pane,
//   help), navigation tree, eight views, details pane and preview pane.
FocusScope {
    id: ex
    property var frame: null
    property string path: ""

    // ---- location & history
    property string location: ""
    property var history: []
    property int historyIndex: -1
    readonly property bool computerView: location === "::computer"
    readonly property bool librariesView: location === "::libraries"
    readonly property bool virtualView: location.indexOf("::") === 0
    readonly property bool trashView: location === Files.trash
    readonly property bool searchMode: dir.searchText.length > 0
    readonly property var library: libraryFor(location)

    // ---- view state
    property string viewMode: "details"
    property var viewModes: ({})          // per-folder choice, like Explorer remembers
    property var selected: ({})
    property int current: -1
    property int anchor: -1
    property string renaming: ""
    property bool showHidden: false
    property bool menuBarPinned: false
    property bool menuBarShown: false
    property bool detailsPaneShown: true
    property bool previewPaneShown: false
    property bool navPaneShown: true
    property bool statusBarShown: false
    property real navWidth: 196
    property real previewWidth: 280
    property var expanded: ({ "::favorites": true, "::libraries": true, "::computer": true })
    property int treeRev: 0
    property string typeAhead: ""
    // Drag and drop
    property bool dragging: false
    property var dragPaths: []
    property point pressPos: Qt.point(0, 0)

    readonly property var libraries: [
        { name: "Documents", path: Files.documents, icon: "folder-documents" },
        { name: "Music", path: Files.music, icon: "folder-music" },
        { name: "Pictures", path: Files.pictures, icon: "folder-pictures" },
        { name: "Videos", path: Files.videos, icon: "folder-videos" }
    ]
    readonly property var viewList: [
        { id: "extralarge", text: "Extra large icons" },
        { id: "large", text: "Large icons" },
        { id: "medium", text: "Medium icons" },
        { id: "small", text: "Small icons" },
        { id: "list", text: "List" },
        { id: "details", text: "Details" },
        { id: "tiles", text: "Tiles" },
        { id: "content", text: "Content" }
    ]
    readonly property var gridSpec: ({
        extralarge: { w: 172, h: 196, icon: 128 },
        large: { w: 118, h: 140, icon: 96 },
        medium: { w: 86, h: 94, icon: 48 },
        small: { w: 214, h: 22, icon: 16 },
        list: { w: 230, h: 22, icon: 16 },
        tiles: { w: 262, h: 64, icon: 48 }
    })
    readonly property bool gridMode: gridSpec[viewMode] !== undefined
    readonly property var spec: gridMode ? gridSpec[viewMode] : gridSpec.small

    // Details columns (widths are user-resizable)
    property real colName: 240
    property real colDate: 140
    property real colType: 140
    property real colSize: 86
    property real colFolder: 220

    readonly property color headingBlue: Theme.c("#1e3287")
    readonly property color linkBlue: Theme.c("#0066cc")
    readonly property color cmdText: Theme.c("#1e395b")

    Component.onCompleted: navigate(path.length > 0 ? path : Files.home, true)
    onPathChanged: if (path.length > 0 && path !== location) navigate(path, true)
    onFrameChanged: if (frame) { frame.internalBareCaption = true; updateTitle() }
    onSearchModeChanged: updateTitle()

    DirModel {
        id: dir
        path: ex.virtualView ? "" : ex.location
        showHidden: ex.showHidden
        onCountChanged: if (ex.current >= count) ex.current = count - 1
    }
    Timer { id: searchDelay; interval: 380; onTriggered: dir.searchText = searchField.text }
    Timer { id: typeAheadReset; interval: 1000; onTriggered: ex.typeAhead = "" }

    // What the pointer carries while dragging files: drawn above every window
    // so it can be dropped on folders here, in other Explorer windows or in
    // the navigation tree.
    Item {
        id: dragGhost
        parent: Shell.root
        z: 100000
        width: 64; height: 64
        visible: ex.dragging
        property var paths: ex.dragPaths
        property bool copy: false
        Drag.active: ex.dragging
        Drag.keys: ["vitrum-files"]
        Drag.hotSpot.x: 20
        Drag.hotSpot.y: 20
        AppIcon {
            size: 48
            opacity: 0.75
            name: dragGhost.paths.length ? ex.fileIcon(Files.iconName(dragGhost.paths[0]), Files.isDir(dragGhost.paths[0]), dragGhost.paths[0]) : ""
        }
        Rectangle {
            visible: dragGhost.paths.length > 1
            x: 34; y: 30
            width: Math.max(18, countText.implicitWidth + 8); height: 18
            radius: 9
            color: Theme.c("#2a6fc0")
            border.color: Theme.c("white")
            VText { id: countText; anchors.centerIn: parent; text: dragGhost.paths.length; color: Theme.c("white"); font.pixelSize: Theme.fontSizeSmall }
        }
        Rectangle {
            visible: dragGhost.copy
            x: 34; y: 4
            width: 16; height: 16; radius: 3
            color: Theme.c("white"); border.color: Theme.c("#7a8ea6")
            VText { anchors.centerIn: parent; text: "+"; font.bold: true; color: Theme.c("#1e5fb3") }
        }
    }
    function dragMove(filePath, item, m) {
        const g = item.mapToItem(Shell.root, m.x, m.y)
        if (!dragging) {
            if (Math.abs(g.x - pressPos.x) + Math.abs(g.y - pressPos.y) < 8)
                return
            if (renaming.length) return
            dragPaths = selected[filePath] ? selectedPaths() : [filePath]
            dragging = true
        }
        dragGhost.copy = (m.modifiers & Qt.ControlModifier) !== 0
        dragGhost.x = g.x - dragGhost.Drag.hotSpot.x
        dragGhost.y = g.y - dragGhost.Drag.hotSpot.y
    }
    function dragEnd() {
        if (!dragging) return false
        dragGhost.Drag.drop()
        dragging = false
        dragPaths = []
        return true
    }
    // Drop handling shared by folders, the view background and the tree.
    function canDropOn(target, src) {
        if (!src || !src.paths || src.paths.length === 0 || target.length === 0 || target.indexOf("::") === 0)
            return false
        return !src.paths.some(p => p === target || target.indexOf(p + "/") === 0)
    }
    function dropOn(target, src) {
        if (!canDropOn(target, src)) return false
        const paths = src.paths.slice()
        const ok = target === Files.trash ? Files.moveToTrash(paths) : Files.transfer(paths, target, src.copy)
        refresh()
        return ok
    }

    // ================================================================ logic
    function libraryFor(p) {
        for (let i = 0; i < libraries.length; ++i)
            if (p === libraries[i].path || p.indexOf(libraries[i].path + "/") === 0)
                return libraries[i]
        return null
    }
    function titleFor(p) {
        if (p === "::computer") return "Computer"
        if (p === "::libraries") return "Libraries"
        if (p === Files.trash) return "Recycle Bin"
        if (p === Files.home) return Sys.realName
        if (p === "/") return Files.volumeLabel("/")
        const lib = libraryFor(p)
        if (lib && lib.path === p) return lib.name
        return Files.displayName(p)
    }
    function folderIcon(p) {
        if (p === "::computer") return Theme.icon("computer")
        if (p === "::libraries") return Theme.icon("library")
        if (p === "::favorites") return Theme.icon("star")
        if (p === Files.trash) return Theme.icon(Files.trashCount() > 0 ? "trash-full" : "trash-empty")
        if (p === Files.home) return Theme.icon("user-home")
        if (p === Files.desktop) return Theme.icon("desktop-folder")
        if (p === Files.downloads) return Theme.icon("folder-downloads")
        if (p === Files.documents) return Theme.icon("folder-documents")
        if (p === Files.music) return Theme.icon("folder-music")
        if (p === Files.pictures) return Theme.icon("folder-pictures")
        if (p === Files.videos) return Theme.icon("folder-videos")
        if (p === "/" || Files.volumes().some(v => v.path === p)) return Theme.icon("drive")
        return Theme.icon("folder")
    }
    function fileIcon(icon, isDir, p) {
        return isDir ? folderIcon(p) : Theme.themeIcon(icon, "text-x-generic")
    }
    function updateTitle() {
        if (!frame)
            return
        frame.internalTitle = searchMode ? "Search Results in " + titleFor(location) : titleFor(location)
        frame.internalIcon = folderIcon(location)
    }
    function navigate(p, push) {
        if (p.indexOf("::") !== 0 && !Files.isDir(p))
            return
        renaming = ""
        selected = {}
        current = -1
        anchor = -1
        searchField.text = ""
        searchDelay.stop()
        dir.searchText = ""
        if (push) {
            const h = history.slice(0, historyIndex + 1)
            if (h[h.length - 1] !== p)
                h.push(p)
            history = h.slice(-30)
            historyIndex = history.length - 1
        }
        location = p
        if (path !== p)
            path = p
        // Pictures and videos open in Large icons, everything else in Details,
        // unless the user picked a view for that folder.
        const lib = libraryFor(p)
        viewMode = viewModes[p] || (lib && (lib.name === "Pictures" || lib.name === "Videos") ? "large" : "details")
        updateTitle()
        ex.forceActiveFocus()
    }
    function setView(v) {
        viewMode = v
        const m = Object.assign({}, viewModes)
        m[location] = v
        viewModes = m
    }
    function back() { if (historyIndex > 0) { historyIndex--; navigate(history[historyIndex], false) } }
    function forward() { if (historyIndex < history.length - 1) { historyIndex++; navigate(history[historyIndex], false) } }
    function up() {
        if (location === "::computer" || location === "::libraries") return
        const lib = libraryFor(location)
        if (lib && lib.path === location) return navigate("::libraries", true)
        if (location === "/" || location === Files.trash) return navigate("::computer", true)
        navigate(Files.parentDir(location), true)
    }
    function refresh() { dir.refresh(); treeRev++ }
    function open(p) {
        if (p.indexOf("::") === 0 || Files.isDir(p))
            navigate(p, true)
        else
            Shell.openFile(p)
    }
    function selectedPaths() { return Object.keys(selected).filter(k => selected[k]) }
    function selectOnly(p) { const s = {}; if (p) s[p] = true; selected = s }
    function selectIndex(i, mods) {
        if (i < 0 || i >= dir.count) return
        const p = dir.pathAt(i)
        if (mods & Qt.ShiftModifier && anchor >= 0) {
            const s = (mods & Qt.ControlModifier) ? Object.assign({}, selected) : {}
            const a = Math.min(anchor, i), b = Math.max(anchor, i)
            for (let k = a; k <= b; ++k) s[dir.pathAt(k)] = true
            selected = s
        } else if (mods & Qt.ControlModifier) {
            const s = Object.assign({}, selected)
            s[p] = !s[p]
            selected = s
            anchor = i
        } else {
            selectOnly(p)
            anchor = i
        }
        current = i
        activeView().positionViewAtIndex(i, GridView.Contain)
    }
    function selectAll() { const s = {}; for (let i = 0; i < dir.count; ++i) s[dir.pathAt(i)] = true; selected = s }
    function invertSelection() { const s = {}; for (let i = 0; i < dir.count; ++i) { const p = dir.pathAt(i); if (!selected[p]) s[p] = true } selected = s }
    function activeView() { return gridMode ? grid : list }
    function newFolder() { const p = Files.makeFolder(location); if (p) { refresh(); selectOnly(p); renaming = p } }
    function newTextFile() { const p = Files.makeFile(location); if (p) { refresh(); selectOnly(p); renaming = p } }
    function deleteSelection() { const s = selectedPaths(); if (s.length) { Files.moveToTrash(s); selected = {} } }
    function canPaste() { return Files.clipboard.length > 0 && !virtualView }

    // Arrow keys move like Explorer: in grids by cell, in List by column.
    function step(key) {
        const n = dir.count
        if (n === 0) return -1
        if (current < 0) return 0
        let i = current
        if (viewMode === "list") {
            const rows = Math.max(1, Math.floor(grid.height / spec.h))
            if (key === Qt.Key_Up) i -= 1
            else if (key === Qt.Key_Down) i += 1
            else if (key === Qt.Key_Left) i -= rows
            else if (key === Qt.Key_Right) i += rows
        } else if (gridMode) {
            const cols = Math.max(1, Math.floor(grid.width / spec.w))
            if (key === Qt.Key_Left) i -= 1
            else if (key === Qt.Key_Right) i += 1
            else if (key === Qt.Key_Up) i -= cols
            else if (key === Qt.Key_Down) i += cols
        } else {
            if (key === Qt.Key_Up) i -= 1
            else if (key === Qt.Key_Down) i += 1
        }
        if (key === Qt.Key_Home) i = 0
        if (key === Qt.Key_End) i = n - 1
        if (key === Qt.Key_PageDown) i += 10
        if (key === Qt.Key_PageUp) i -= 10
        return Math.max(0, Math.min(n - 1, i))
    }

    Keys.onPressed: (e) => {
        const ctrl = e.modifiers & Qt.ControlModifier
        const alt = e.modifiers & Qt.AltModifier
        if (e.key === Qt.Key_Alt) { if (!menuBarPinned) menuBarShown = !menuBarShown; e.accepted = true; return }
        if (e.key === Qt.Key_Backspace || (e.key === Qt.Key_Left && alt)) back()
        else if (e.key === Qt.Key_Right && alt) forward()
        else if (e.key === Qt.Key_Up && alt) up()
        else if ([Qt.Key_Up, Qt.Key_Down, Qt.Key_Left, Qt.Key_Right, Qt.Key_Home, Qt.Key_End, Qt.Key_PageUp, Qt.Key_PageDown].indexOf(e.key) >= 0) {
            const i = step(e.key)
            if (i >= 0) {
                if (ctrl && !(e.modifiers & Qt.ShiftModifier)) { current = i; activeView().positionViewAtIndex(i, GridView.Contain) }
                else selectIndex(i, e.modifiers & Qt.ShiftModifier)
            }
        }
        else if (e.key === Qt.Key_Space && ctrl && current >= 0) selectIndex(current, Qt.ControlModifier)
        else if (e.key === Qt.Key_Delete) deleteSelection()
        else if (e.key === Qt.Key_F2) { const s = selectedPaths(); if (s.length === 1) renaming = s[0] }
        else if (e.key === Qt.Key_F3 || (ctrl && (e.key === Qt.Key_F || e.key === Qt.Key_E))) searchField.input.forceActiveFocus()
        else if (e.key === Qt.Key_F4 || (ctrl && e.key === Qt.Key_L) || (alt && e.key === Qt.Key_D)) address.editing = true
        else if (e.key === Qt.Key_F5 || (ctrl && e.key === Qt.Key_R)) refresh()
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { if (alt) { const s = selectedPaths(); Shell.openProperties(s[0] || location) } else selectedPaths().forEach(p => open(p)) }
        else if (alt && e.key === Qt.Key_P) previewPaneShown = !previewPaneShown
        else if (ctrl && e.key === Qt.Key_C) Files.copy(selectedPaths())
        else if (ctrl && e.key === Qt.Key_X) Files.cut(selectedPaths())
        else if (ctrl && e.key === Qt.Key_V) { if (canPaste()) Files.paste(location) }
        else if (ctrl && e.key === Qt.Key_A) selectAll()
        else if (ctrl && e.key === Qt.Key_W) { if (frame) frame.close() }
        else if (ctrl && e.key === Qt.Key_N && (e.modifiers & Qt.ShiftModifier)) newFolder()
        else if (ctrl && e.key === Qt.Key_N) Shell.openExplorer(virtualView ? "" : location)
        else if (ctrl && (e.modifiers & Qt.ShiftModifier) && e.key >= Qt.Key_1 && e.key <= Qt.Key_8) setView(viewList[e.key - Qt.Key_1].id)
        else if (!ctrl && !alt && e.text.length === 1 && e.text > " ") {
            // Type to select: jump to the next item whose name starts with what was typed.
            typeAhead += e.text.toLowerCase()
            typeAheadReset.restart()
            for (let k = 0; k < dir.count; ++k) {
                const i = (Math.max(0, current) + (typeAhead.length === 1 ? 1 : 0) + k) % dir.count
                if (dir.get(i).name.toLowerCase().indexOf(typeAhead) === 0) { selectIndex(i, 0); break }
            }
        }
        else return
        e.accepted = true
    }

    // ---- menus
    function viewEntries() {
        return viewList.map(v => ({ text: v.text, checked: viewMode === v.id, action: () => ex.setView(v.id) }))
    }
    function sortEntries() {
        return [
            { text: "Sort by Name", checked: dir.sortField === "name", action: () => dir.sortField = "name" },
            { text: "Sort by Date modified", checked: dir.sortField === "modified", action: () => dir.sortField = "modified" },
            { text: "Sort by Type", checked: dir.sortField === "type", action: () => dir.sortField = "type" },
            { text: "Sort by Size", checked: dir.sortField === "size", action: () => dir.sortField = "size" },
            { separator: true },
            { text: "Ascending", checked: !dir.sortDescending, action: () => dir.sortDescending = false },
            { text: "Descending", checked: dir.sortDescending, action: () => dir.sortDescending = true }
        ]
    }
    function layoutEntries() {
        return [
            { text: "Menu bar", checked: menuBarPinned, action: () => { ex.menuBarPinned = !ex.menuBarPinned; ex.menuBarShown = ex.menuBarPinned } },
            { text: "Details pane", checked: detailsPaneShown, action: () => ex.detailsPaneShown = !ex.detailsPaneShown },
            { text: "Preview pane", checked: previewPaneShown, action: () => ex.previewPaneShown = !ex.previewPaneShown },
            { text: "Navigation pane", checked: navPaneShown, action: () => ex.navPaneShown = !ex.navPaneShown }
        ]
    }
    function popupAt(item, entries) {
        const g = item.mapToItem(Shell.root, 0, item.height)
        Shell.showMenu(entries, g.x, g.y)
    }
    function organizeMenu(item) {
        const sel = selectedPaths()
        popupAt(item, [
            { text: "Cut", enabled: sel.length > 0, action: () => Files.cut(ex.selectedPaths()) },
            { text: "Copy", enabled: sel.length > 0, action: () => Files.copy(ex.selectedPaths()) },
            { text: "Paste", enabled: canPaste(), action: () => Files.paste(ex.location) },
            { separator: true },
            { text: "Select all", action: () => ex.selectAll() },
            { separator: true }
        ].concat(layoutEntries().map(e => Object.assign(e, { text: "Layout: " + e.text }))).concat([
            { text: "Folder and search options", action: () => ex.folderOptionsMenu(item) },
            { separator: true },
            { text: "Delete", enabled: sel.length > 0, action: () => ex.deleteSelection() },
            { text: "Rename", enabled: sel.length === 1, action: () => ex.renaming = sel[0] },
            { separator: true },
            { text: "Properties", action: () => Shell.openProperties(sel[0] || (ex.virtualView ? Files.home : ex.location)) },
            { text: "Close", action: () => { if (ex.frame) ex.frame.close() } }
        ]))
    }
    function folderOptionsMenu(item) {
        popupAt(item, [
            { text: "Show hidden files, folders and drives", checked: showHidden, action: () => ex.showHidden = !ex.showHidden },
            { text: "Show status bar", checked: statusBarShown, action: () => ex.statusBarShown = !ex.statusBarShown }
        ])
    }
    function menuBarMenu(name, item) {
        const sel = selectedPaths()
        let entries = []
        if (name === "File") entries = [
            { text: "Open new window", action: () => Shell.openExplorer(ex.virtualView ? "" : ex.location) },
            { text: "Open command window here", icon: Theme.icon("terminal"), enabled: !ex.virtualView, action: () => Launcher.openTerminal(ex.location) },
            { separator: true },
            { text: "New folder", enabled: !ex.virtualView, action: () => ex.newFolder() },
            { text: "New text document", enabled: !ex.virtualView, action: () => ex.newTextFile() },
            { separator: true },
            { text: "Delete", enabled: sel.length > 0, action: () => ex.deleteSelection() },
            { text: "Rename", enabled: sel.length === 1, action: () => ex.renaming = sel[0] },
            { text: "Properties", action: () => Shell.openProperties(sel[0] || (ex.virtualView ? Files.home : ex.location)) },
            { separator: true },
            { text: "Close", action: () => { if (ex.frame) ex.frame.close() } }
        ]
        else if (name === "Edit") entries = [
            { text: "Cut\tCtrl+X", enabled: sel.length > 0, action: () => Files.cut(ex.selectedPaths()) },
            { text: "Copy\tCtrl+C", enabled: sel.length > 0, action: () => Files.copy(ex.selectedPaths()) },
            { text: "Paste\tCtrl+V", enabled: canPaste(), action: () => Files.paste(ex.location) },
            { separator: true },
            { text: "Select all\tCtrl+A", action: () => ex.selectAll() },
            { text: "Invert selection", action: () => ex.invertSelection() }
        ]
        else if (name === "View") entries = [
            { text: "Status bar", checked: statusBarShown, action: () => ex.statusBarShown = !ex.statusBarShown },
            { separator: true }
        ].concat(viewEntries()).concat([{ separator: true }]).concat(sortEntries()).concat([
            { separator: true },
            { text: "Refresh\tF5", action: () => ex.refresh() }
        ])
        else if (name === "Tools") entries = [
            { text: "Show hidden files and folders", checked: showHidden, action: () => ex.showHidden = !ex.showHidden },
            { text: "Control Panel", action: () => Shell.openSettings("") }
        ]
        else if (name === "Help") entries = [
            { text: "About Vitrum", action: () => Shell.openAbout() }
        ]
        popupAt(item, entries)
    }
    function itemMenu(p, gx, gy) {
        if (!selected[p])
            selectOnly(p)
        const isDir = Files.isDir(p)
        const entries = [{ text: "Open", bold: true, action: () => ex.open(p) }]
        if (Compat.isCompatFile(p))
            entries.push({ text: "Run", icon: Theme.icon("exe"), action: () => Shell.openFile(p) })
        if (!isDir && Files.isText(p))
            entries.push({ text: "Edit", action: () => Shell.openInternal("notepad", { path: p }) })
        if (!isDir && Files.isImage(p))
            entries.push({ text: "Edit with Paint", icon: Theme.icon("paint"), action: () => Shell.openInternal("paint", { path: p }) })
        if (isDir)
            entries.push({ text: "Open in new window", action: () => Shell.openExplorer(p) })
        if (Apps.isProgramFile(p)) {
            entries.push({ text: "Pin to Taskbar", icon: Theme.icon("pin"), action: () => { const id = Apps.ensureEntryForFile(p); if (id) Prefs.pin(id) } })
            entries.push({ text: "Pin to Start Menu", action: () => { const id = Apps.ensureEntryForFile(p); if (id) Prefs.pinToStart(id) } })
        }
        entries.push({ text: "Open command window here", icon: Theme.icon("terminal"), action: () => Launcher.openTerminal(isDir ? p : Files.parentDir(p)) })
        entries.push({ separator: true })
        entries.push({ text: "Cut", action: () => Files.cut(ex.selectedPaths()) })
        entries.push({ text: "Copy", action: () => Files.copy(ex.selectedPaths()) })
        if (isDir)
            entries.push({ text: "Paste", enabled: Files.clipboard.length > 0, action: () => Files.paste(p) })
        entries.push({ separator: true })
        entries.push({ text: "Delete", action: () => ex.deleteSelection() })
        entries.push({ text: "Rename", action: () => ex.renaming = p })
        if (searchMode)
            entries.push({ text: "Open file location", action: () => ex.navigate(Files.parentDir(p), true) })
        entries.push({ separator: true })
        entries.push({ text: "Properties", action: () => Shell.openProperties(p) })
        Shell.showMenu(entries, gx, gy)
    }
    function backgroundMenu(gx, gy) {
        if (virtualView)
            return
        const entries = viewEntries().concat([{ separator: true }]).concat(sortEntries().slice(0, 4)).concat([
            { separator: true },
            { text: "Refresh", action: () => ex.refresh() },
            { separator: true },
            { text: "Paste", enabled: ex.canPaste(), action: () => Files.paste(ex.location) },
            { separator: true },
            { text: "New folder", icon: Theme.icon("folder"), action: () => ex.newFolder() },
            { text: "New text document", icon: Theme.icon("file-text"), action: () => ex.newTextFile() },
            { separator: true },
            { text: "Open command window here", icon: Theme.icon("terminal"), action: () => Launcher.openTerminal(ex.location) },
            { text: "Properties", action: () => Shell.openProperties(ex.location) }
        ])
        Shell.showMenu(entries, gx, gy)
    }

    // ---- breadcrumbs
    function crumbs() {
        const p = location
        if (p === "::computer") return [{ name: "Computer", path: "::computer" }]
        if (p === "::libraries") return [{ name: "Libraries", path: "::libraries" }]
        if (p === Files.trash) return [{ name: "Recycle Bin", path: Files.trash }]
        const out = []
        let base = ""
        const lib = libraryFor(p)
        if (lib) {
            out.push({ name: "Libraries", path: "::libraries" }, { name: lib.name, path: lib.path })
            base = lib.path
        } else if (p === Files.home || p.indexOf(Files.home + "/") === 0) {
            out.push({ name: Sys.realName, path: Files.home })
            base = Files.home
        } else {
            out.push({ name: "Computer", path: "::computer" }, { name: Files.volumeLabel("/"), path: "/" })
            base = ""
        }
        const rest = p.substring(base.length).split("/").filter(s => s.length)
        let acc = base
        for (let i = 0; i < rest.length; ++i) {
            acc += "/" + rest[i]
            out.push({ name: Files.displayName(acc), path: acc })
        }
        return out
    }
    function childrenOf(p) {
        if (p === "::root") return [
            { name: "Desktop", path: Files.desktop },
            { name: "Libraries", path: "::libraries" },
            { name: Sys.realName, path: Files.home },
            { name: "Computer", path: "::computer" },
            { name: "Recycle Bin", path: Files.trash }
        ]
        if (p === "::computer") return drives().map(d => ({ name: d.name, path: d.path }))
        if (p === "::libraries") return libraries.map(l => ({ name: l.name, path: l.path }))
        if (p === "::favorites") return [{ name: "Desktop", path: Files.desktop }, { name: "Downloads", path: Files.downloads }]
        return Files.subfolders(p, showHidden)
    }
    function crumbMenu(p, item) {
        const kids = childrenOf(p)
        if (kids.length === 0) return
        popupAt(item, kids.slice(0, 40).map(k => ({ text: k.name, icon: ex.folderIcon(k.path), bold: ex.location === k.path || ex.location.indexOf(k.path + "/") === 0, action: () => ex.navigate(k.path, true) })))
    }
    function drives() {
        const v = Files.volumes()
        if (Compat.windowsAvailable)
            v.push({ name: "Windows Programs", path: Compat.prefix + "/drive_c", total: 0, free: 0, removable: false, other: true })
        return v
    }

    // ---- navigation tree (flattened)
    function treeRows() {
        treeRev
        const rows = []
        const add = (name, p, icon, depth, expandable) => {
            const open = expanded[p] === true
            rows.push({ name: name, path: p, icon: icon, depth: depth, expandable: expandable, open: open })
            return open
        }
        const addFolder = (name, p, depth) => {
            if (add(name, p, folderIcon(p), depth, Files.hasSubfolders(p)))
                Files.subfolders(p, showHidden).forEach(c => addFolder(c.name, c.path, depth + 1))
        }
        if (add("Favorites", "::favorites", Theme.icon("star"), 0, true)) {
            add("Desktop", Files.desktop, folderIcon(Files.desktop), 1, false)
            add("Downloads", Files.downloads, folderIcon(Files.downloads), 1, false)
        }
        rows.push({ gap: true })
        if (add("Libraries", "::libraries", Theme.icon("library"), 0, true))
            libraries.forEach(l => addFolder(l.name, l.path, 1))
        rows.push({ gap: true })
        if (add(Sys.realName, Files.home, Theme.icon("user-home"), 0, true))
            Files.subfolders(Files.home, showHidden).forEach(c => addFolder(c.name, c.path, 1))
        rows.push({ gap: true })
        if (add("Computer", "::computer", Theme.icon("computer"), 0, true))
            drives().forEach(d => addFolder(d.name, d.path, 1))
        rows.push({ gap: true })
        add("Recycle Bin", Files.trash, folderIcon(Files.trash), 0, false)
        return rows
    }
    function toggleNode(p) {
        const e = Object.assign({}, expanded)
        e[p] = !e[p]
        expanded = e
    }

    // ================================================================ UI
    component Chevron: Canvas {
        // Small solid triangle pointing down (or right when `right`).
        property bool pointRight: false
        property color color: Theme.c("#3b3b3b")
        width: 7; height: 7
        onColorChanged: requestPaint()
        onPointRightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d")
            c.reset()
            c.fillStyle = color
            c.beginPath()
            if (pointRight) { c.moveTo(2, 0); c.lineTo(6, 3.5); c.lineTo(2, 7) }
            else { c.moveTo(0, 2); c.lineTo(7, 2); c.lineTo(3.5, 6) }
            c.closePath()
            c.fill()
        }
    }

    // A command-bar style button: flat until hovered.
    component CmdButton: Item {
        id: cb
        property string text: ""
        property string iconName: ""
        property bool dropDown: false
        property bool on: true
        property bool checked: false
        signal clicked()
        width: cbRow.implicitWidth + 16
        height: 24
        opacity: on ? 1 : 0.45
        Rectangle {
            anchors.fill: parent
            radius: 3
            visible: cb.on && (cbMouse.containsMouse || cb.checked)
            border.color: Theme.c("#7da2ce")
            gradient: Gradient {
                GradientStop { position: 0; color: cbMouse.pressed ? Theme.c("#c8dbf1") : Theme.c("#fbfdff") }
                GradientStop { position: 0.5; color: cbMouse.pressed ? Theme.c("#bfd5ef") : Theme.c("#e6f0fb") }
                GradientStop { position: 1; color: cbMouse.pressed ? Theme.c("#cfe0f3") : Theme.c("#d5e5f8") }
            }
            Rectangle { anchors.fill: parent; anchors.margins: 1; radius: 2; color: "transparent"; border.color: Qt.rgba(1, 1, 1, 0.7) }
        }
        Row {
            id: cbRow
            anchors.centerIn: parent
            spacing: 5
            AppIcon { visible: cb.iconName.length > 0; size: 16; name: cb.iconName; anchors.verticalCenter: parent.verticalCenter }
            VText { visible: cb.text.length > 0; text: cb.text; color: ex.cmdText; anchors.verticalCenter: parent.verticalCenter }
            Chevron { visible: cb.dropDown; color: ex.cmdText; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea { id: cbMouse; anchors.fill: parent; hoverEnabled: true; onClicked: if (cb.on) cb.clicked() }
    }

    // Round blue glass back/forward button
    component TravelButton: Item {
        id: tb
        property bool forwardDir: false
        property bool on: true
        signal clicked()
        width: 27; height: 27
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            opacity: tb.on ? 1 : 0.6
            border.color: tb.on ? Theme.c("#1c3e6e") : Theme.c("#5b6e88")
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.c(!tb.on ? "#d8e2ee" : tbMouse.pressed ? "#7fb2e5" : tbMouse.containsMouse ? "#d0ecff" : "#a9d0f5") }
                GradientStop { position: 0.48; color: Theme.c(!tb.on ? "#a5b6cb" : tbMouse.pressed ? "#1f5ea8" : tbMouse.containsMouse ? "#4fa6f0" : "#3f87d6") }
                GradientStop { position: 0.52; color: Theme.c(!tb.on ? "#8fa3bb" : tbMouse.pressed ? "#174e93" : tbMouse.containsMouse ? "#2a8ae6" : "#2a6fc0") }
                GradientStop { position: 1; color: Theme.c(!tb.on ? "#b7c5d6" : tbMouse.pressed ? "#3f86d0" : tbMouse.containsMouse ? "#86d0ff" : "#5aa5e8") }
            }
            Rectangle { anchors.fill: parent; anchors.margins: 1; radius: width / 2; color: "transparent"; border.color: Qt.rgba(1, 1, 1, 0.45) }
            Canvas {
                anchors.centerIn: parent
                width: 14; height: 12
                property bool fwd: tb.forwardDir
                onFwdChanged: requestPaint()
                onPaint: {
                    const c = getContext("2d")
                    c.reset()
                    c.save()
                    if (fwd) { c.translate(14, 0); c.scale(-1, 1) }
                    c.fillStyle = Theme.c("white")
                    c.strokeStyle = Qt.rgba(0, 0.1, 0.3, 0.5)
                    c.lineWidth = 0.8
                    c.beginPath()
                    c.moveTo(0.5, 6); c.lineTo(6.5, 0.5); c.lineTo(6.5, 3.8); c.lineTo(13.5, 3.8)
                    c.lineTo(13.5, 8.2); c.lineTo(6.5, 8.2); c.lineTo(6.5, 11.5); c.closePath()
                    c.fill(); c.stroke()
                    c.restore()
                }
            }
        }
        MouseArea { id: tbMouse; anchors.fill: parent; hoverEnabled: true; onClicked: if (tb.on) tb.clicked() }
    }

    Column {
        id: chrome
        width: parent.width
        z: 2

        // ---- Glass travel band
        Item {
            id: navBar
            width: parent.width
            height: 40
            GlassSurface {
                anchors.fill: parent
                tracking: ex.frame
                intensity: Theme.glassIntensity(ex.frame ? ex.frame.active : true)
                brightness: ex.frame && ex.frame.active ? 0.03 : 0.12
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.10) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.30) }
                }
            }

            // Travel band: back, forward, recent pages
            Rectangle {
                id: travel
                x: 5
                anchors.verticalCenter: parent.verticalCenter
                width: 74; height: 29
                radius: 14
                color: Qt.rgba(1, 1, 1, 0.18)
                border.color: Qt.rgba(0, 0, 0, 0.25)
                Row {
                    x: 1; y: 1
                    TravelButton { on: ex.historyIndex > 0; onClicked: ex.back() }
                    TravelButton { forwardDir: true; on: ex.historyIndex < ex.history.length - 1; onClicked: ex.forward() }
                    Item {
                        width: 18; height: 27
                        Chevron { anchors.centerIn: parent; color: Theme.c("#1c2c44") }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                const h = ex.history
                                const entries = []
                                for (let i = h.length - 1; i >= 0; --i) {
                                    const idx = i
                                    entries.push({ text: ex.titleFor(h[i]), icon: ex.folderIcon(h[i]), checked: i === ex.historyIndex, action: () => { ex.historyIndex = idx; ex.navigate(h[idx], false) } })
                                }
                                ex.popupAt(travel, entries.slice(0, 16))
                            }
                        }
                    }
                }
            }

            // Breadcrumb address bar
            Rectangle {
                id: address
                property bool editing: false
                x: travel.x + travel.width + 6
                width: parent.width - x - searchBox.width - 12
                height: 24
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.dark ? Qt.rgba(0.11, 0.12, 0.13, 0.92) : Qt.rgba(1, 1, 1, 0.94)
                border.color: addrHover.containsMouse || editing ? Theme.c("#3c7fb1") : Qt.rgba(0, 0, 0, 0.42)
                radius: 1
                clip: true
                onEditingChanged: if (editing) {
                    addrInput.text = ex.virtualView ? ex.titleFor(ex.location) : ex.location
                    addrInput.forceActiveFocus()
                    addrInput.selectAll()
                }
                MouseArea { id: addrHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                // Search progress, filled green like the glass-era address bar
                Rectangle {
                    id: searchProgress
                    visible: dir.searching
                    x: 1; y: 1
                    height: parent.height - 2
                    width: (parent.width - 2) * progress
                    property real progress: 0
                    NumberAnimation on progress { running: dir.searching; from: 0.05; to: 0.95; duration: 4000; loops: Animation.Infinite }
                    gradient: Gradient {
                        GradientStop { position: 0; color: Theme.c("#d7f5c8") }
                        GradientStop { position: 1; color: Theme.c("#a8e48f") }
                    }
                }
                AppIcon { x: 4; anchors.verticalCenter: parent.verticalCenter; size: 16; name: ex.folderIcon(ex.location) }
                Row {
                    id: crumbRow
                    visible: !address.editing
                    x: 22
                    height: parent.height
                    readonly property var all: { ex.location; return ex.crumbs() }
                    readonly property var shown: all.length > 5 ? all.slice(all.length - 5) : all
                    // Leading chevron: the top-level places (or the hidden part of a long path)
                    Item {
                        width: 15; height: parent.height
                        Rectangle { anchors.fill: parent; anchors.margins: 2; visible: leadMouse.containsMouse; color: Theme.c("#dceafc"); border.color: Theme.c("#7da2ce"); radius: 1 }
                        VText { visible: crumbRow.all.length > 5; anchors.centerIn: parent; text: "«"; color: Theme.c("#1c2c44") }
                        Chevron { visible: crumbRow.all.length <= 5; anchors.centerIn: parent; pointRight: true; color: Theme.c("#1c2c44") }
                        MouseArea {
                            id: leadMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (crumbRow.all.length > 5)
                                    ex.popupAt(parent, crumbRow.all.slice(0, crumbRow.all.length - 5).reverse().map(c => ({ text: c.name, icon: ex.folderIcon(c.path), action: () => ex.navigate(c.path, true) })))
                                else
                                    ex.crumbMenu("::root", parent)
                            }
                        }
                    }
                    Repeater {
                        model: crumbRow.shown
                        delegate: Row {
                            id: crumb
                            required property var modelData
                            height: crumbRow.height
                            Item {
                                width: crumbText.implicitWidth + 12
                                height: parent.height
                                Rectangle {
                                    anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 2
                                    visible: crumbMouse.containsMouse || chevMouse.containsMouse
                                    radius: 1
                                    border.color: Theme.c("#7da2ce")
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: Theme.c("#f3f8fe") }
                                        GradientStop { position: 1; color: Theme.c("#d4e6fb") }
                                    }
                                }
                                VText { id: crumbText; anchors.centerIn: parent; text: crumb.modelData.name; color: Theme.c("#000000") }
                                MouseArea { id: crumbMouse; anchors.fill: parent; hoverEnabled: true; onClicked: ex.navigate(crumb.modelData.path, true) }
                            }
                            Item {
                                width: 15; height: parent.height
                                Rectangle {
                                    anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 2
                                    visible: crumbMouse.containsMouse || chevMouse.containsMouse
                                    radius: 1
                                    border.color: Theme.c("#7da2ce")
                                    color: chevMouse.containsMouse ? Theme.c("#d4e6fb") : Theme.c("#eaf3fd")
                                }
                                Chevron { anchors.centerIn: parent; pointRight: true; color: Theme.c("#1c2c44") }
                                MouseArea { id: chevMouse; anchors.fill: parent; hoverEnabled: true; onClicked: ex.crumbMenu(crumb.modelData.path, parent) }
                            }
                        }
                    }
                    Item {
                        visible: ex.searchMode
                        width: srText.implicitWidth + 12; height: parent.height
                        VText { id: srText; anchors.centerIn: parent; text: "Search Results in " + ex.titleFor(ex.location) }
                    }
                }
                MouseArea {
                    visible: !address.editing
                    x: crumbRow.x + crumbRow.width
                    width: Math.max(0, parent.width - x - 44)
                    height: parent.height
                    onClicked: address.editing = true
                }
                TextInput {
                    id: addrInput
                    visible: address.editing
                    x: 24
                    width: parent.width - 70
                    height: parent.height
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    selectByMouse: true
                    selectionColor: Theme.c("#3399ff")
                    clip: true
                    onAccepted: {
                        const raw = text.trim()
                        const t = raw.replace(/^~/, Files.home)
                        const word = raw.toLowerCase()
                        address.editing = false
                        if (word === "computer" || word === "my computer" || word === "this pc") ex.navigate("::computer", true)
                        else if (word === "libraries") ex.navigate("::libraries", true)
                        else if (word === "recycle bin") ex.navigate(Files.trash, true)
                        else if (word === "control panel") Shell.openSettings("")
                        else if (/^c:\\?$/i.test(raw)) ex.navigate("/", true)
                        else if (Files.isDir(t)) ex.navigate(t, true)
                        else if (Files.exists(t)) Shell.openFile(t)
                        else if (raw.length) Launcher.runCommand(raw)
                    }
                    onActiveFocusChanged: if (!activeFocus) address.editing = false
                    Keys.onEscapePressed: { address.editing = false; ex.forceActiveFocus() }
                }
                // Recent locations drop-down
                Item {
                    anchors.right: refreshBtn.left
                    width: 18; height: parent.height
                    Chevron { anchors.centerIn: parent; color: Theme.c("#1c2c44") }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            const seen = {}
                            const entries = []
                            for (let i = ex.history.length - 1; i >= 0 && entries.length < 12; --i) {
                                const p = ex.history[i]
                                if (seen[p]) continue
                                seen[p] = true
                                entries.push({ text: p.indexOf("::") === 0 ? ex.titleFor(p) : p, icon: ex.folderIcon(p), action: () => ex.navigate(p, true) })
                            }
                            ex.popupAt(address, entries)
                        }
                    }
                }
                // Refresh (or Go while typing)
                Item {
                    id: refreshBtn
                    anchors.right: parent.right
                    width: 24; height: parent.height
                    Rectangle { width: 1; height: parent.height; color: Theme.c("#c7d3e2") }
                    Rectangle {
                        anchors.fill: parent; anchors.margins: 1; anchors.leftMargin: 2
                        visible: refMouse.containsMouse
                        border.color: Theme.c("#7da2ce")
                        gradient: Gradient {
                            GradientStop { position: 0; color: Theme.c("#f3f8fe") }
                            GradientStop { position: 1; color: Theme.c("#cfe3fa") }
                        }
                    }
                    AppIcon { anchors.centerIn: parent; size: 16; name: address.editing ? Theme.icon("arrow-right") : Theme.icon("refresh-small") }
                    MouseArea {
                        id: refMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: address.editing ? addrInput.accepted() : ex.refresh()
                    }
                }
            }

            // Search box
            Rectangle {
                id: searchBox
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(150, Math.min(260, parent.width * 0.26))
                height: 24
                color: searchField.input.activeFocus ? Theme.c("white") : (Theme.dark ? Qt.rgba(0.11, 0.12, 0.13, 0.85) : Qt.rgba(1, 1, 1, 0.85))
                border.color: searchField.input.activeFocus || searchHover.containsMouse ? Theme.c("#3c7fb1") : Qt.rgba(0, 0, 0, 0.42)
                radius: 1
                MouseArea { id: searchHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                TextField7 {
                    id: searchField
                    anchors.fill: parent
                    anchors.margins: 1
                    placeholder: "Search " + ex.titleFor(ex.location)
                    onTextChanged: { if (text.length === 0) { searchDelay.stop(); dir.searchText = "" } else searchDelay.restart() }
                    onAccepted: { searchDelay.stop(); dir.searchText = text }
                    Keys.onEscapePressed: { text = ""; ex.forceActiveFocus() }
                }
                Item {
                    anchors.right: parent.right
                    width: 24; height: parent.height
                    AppIcon {
                        anchors.centerIn: parent
                        size: 16
                        name: searchField.text.length ? Theme.icon("close") : Theme.icon("search")
                        opacity: 0.8
                    }
                    MouseArea { anchors.fill: parent; enabled: searchField.text.length > 0; onClicked: { searchField.text = ""; ex.forceActiveFocus() } }
                }
            }
        }

        // ---- Menu bar (Alt or Organize > Layout > Menu bar)
        Rectangle {
            id: menuBar
            visible: ex.menuBarShown || ex.menuBarPinned
            width: parent.width
            height: visible ? 22 : 0
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.c("#fbfcfe") }
                GradientStop { position: 1; color: Theme.c("#eef3fa") }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.c("#d5dfe9") }
            Row {
                x: 2
                height: parent.height
                Repeater {
                    model: ["File", "Edit", "View", "Tools", "Help"]
                    delegate: Item {
                        id: mbItem
                        required property string modelData
                        width: mbText.implicitWidth + 16
                        height: menuBar.height
                        Rectangle {
                            anchors.fill: parent; anchors.margins: 1
                            visible: mbMouse.containsMouse
                            color: Theme.c("#dceafc"); border.color: Theme.c("#7da2ce"); radius: 2
                        }
                        VText { id: mbText; anchors.centerIn: parent; text: mbItem.modelData }
                        MouseArea {
                            id: mbMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { ex.menuBarMenu(mbItem.modelData, mbItem); if (!ex.menuBarPinned) ex.menuBarShown = false }
                        }
                    }
                }
            }
        }

        // ---- Command bar
        Rectangle {
            id: commandBar
            width: parent.width
            height: 32
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.c("#f6f9fd") }
                GradientStop { position: 0.5; color: Theme.c("#e8eff8") }
                GradientStop { position: 0.51; color: Theme.c("#dfe8f4") }
                GradientStop { position: 1; color: Theme.c("#dbe6f4") }
            }
            Rectangle { width: parent.width; height: 1; color: Theme.dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.9) }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.c("#a0afc3") }
            readonly property var sel: ex.selectedPaths()
            readonly property string one: sel.length === 1 ? sel[0] : ""
            readonly property bool oneIsDir: one.length > 0 && Files.isDir(one)
            Row {
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                CmdButton { id: organizeBtn; text: "Organize"; dropDown: true; onClicked: ex.organizeMenu(organizeBtn) }
                CmdButton {
                    id: openBtn
                    visible: commandBar.one.length > 0 && !commandBar.oneIsDir
                    text: "Open"
                    iconName: visible ? Theme.themeIcon(Files.iconName(commandBar.one), "text-x-generic") : ""
                    dropDown: visible && (Files.isText(commandBar.one) || Files.isImage(commandBar.one))
                    onClicked: {
                        const p = commandBar.one
                        if (Files.isText(p))
                            ex.popupAt(openBtn, [{ text: "Notepad", icon: Theme.icon("notepad"), bold: true, action: () => Shell.openInternal("notepad", { path: p }) }])
                        else if (Files.isImage(p))
                            ex.popupAt(openBtn, [{ text: "Photo Viewer", icon: Theme.icon("image-file"), bold: true, action: () => Shell.openInternal("photos", { path: p }) },
                                                 { text: "Paint", icon: Theme.icon("paint"), action: () => Shell.openInternal("paint", { path: p }) }])
                        else Shell.openFile(p)
                    }
                }
                CmdButton { visible: commandBar.oneIsDir; text: "Open"; onClicked: ex.open(commandBar.one) }
                CmdButton { visible: ex.computerView; text: "System properties"; onClicked: Shell.openAbout() }
                CmdButton { visible: ex.computerView; text: "Open Control Panel"; onClicked: Shell.openSettings("") }
                CmdButton { visible: ex.trashView; text: "Empty the Recycle Bin"; on: dir.count > 0; onClicked: { Files.emptyTrash(); ex.refresh() } }
                CmdButton { visible: commandBar.sel.length > 0 && !ex.trashView && !ex.virtualView; text: "Delete"; onClicked: ex.deleteSelection() }
                CmdButton { visible: !ex.virtualView && !ex.trashView && commandBar.sel.length === 0; text: "New folder"; onClicked: ex.newFolder() }
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                CmdButton { id: viewBtn; iconName: Theme.icon("view"); onClicked: { const i = ex.viewList.findIndex(v => v.id === ex.viewMode); ex.setView(ex.viewList[(i + 1) % ex.viewList.length].id) } }
                CmdButton { id: viewDrop; width: 16; dropDown: true; onClicked: ex.popupAt(viewDrop, ex.viewEntries()) }
                Item { width: 4; height: 1 }
                CmdButton { iconName: Theme.icon("preview-pane"); checked: ex.previewPaneShown; onClicked: ex.previewPaneShown = !ex.previewPaneShown }
                CmdButton { iconName: Theme.icon("help"); onClicked: Shell.openAbout() }
            }
        }
    }

    // ================================================================ body
    Item {
        id: body
        y: chrome.height
        width: parent.width
        height: parent.height - y - detailsPane.height - statusBar.height

        // ---- Navigation pane
        Rectangle {
            id: navPane
            visible: ex.navPaneShown
            width: visible ? ex.navWidth : 0
            height: parent.height
            color: Theme.c("white")
            MouseArea { id: navHover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
            ListView {
                id: tree
                anchors.fill: parent
                anchors.topMargin: 4
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: ex.navPaneShown ? ex.treeRows() : []
                delegate: Item {
                    id: row
                    required property var modelData
                    width: tree.width
                    height: modelData.gap ? 10 : 22
                    readonly property bool gap: modelData.gap === true
                    readonly property bool here: !gap && ex.location === modelData.path
                    readonly property real indent: 4 + (modelData.depth || 0) * 16
                    readonly property bool act: ex.frame ? ex.frame.active : true
                    Rectangle {
                        visible: !row.gap && (row.here || rowMouse.containsMouse || rowDrop.containsDrag)
                        x: 2; width: parent.width - 4; height: parent.height
                        radius: 2
                        border.color: Theme.c(row.here ? (row.act ? "#84acdd" : "#d9d9d9") : "#b8d6fb")
                        gradient: Gradient {
                            GradientStop { position: 0; color: Theme.c(row.here ? (row.act ? "#e2eefc" : "#f8f8f8") : "#f8fbfe") }
                            GradientStop { position: 1; color: Theme.c(row.here ? (row.act ? "#c6dff9" : "#e5e5e5") : "#e8f2fd") }
                        }
                    }
                    DropArea {
                        id: rowDrop
                        anchors.fill: parent
                        enabled: !row.gap && row.modelData.path.indexOf("::") !== 0
                        keys: ["vitrum-files"]
                        onEntered: (d) => { if (!ex.canDropOn(row.modelData.path, d.source)) d.accepted = false }
                        onDropped: (d) => { if (ex.dropOn(row.modelData.path, d.source)) d.accept() }
                    }
                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        enabled: !row.gap
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (m) => {
                            const p = row.modelData.path
                            if (m.button === Qt.RightButton) {
                                const g = mapToItem(Shell.root, m.x, m.y)
                                Shell.showMenu([
                                    { text: row.modelData.open ? "Collapse" : "Expand", enabled: row.modelData.expandable, bold: true, action: () => ex.toggleNode(p) },
                                    { text: "Open in new window", enabled: p !== "::favorites", action: () => Shell.openExplorer(p.indexOf("::") === 0 ? "" : p) },
                                    { separator: true },
                                    { text: "Properties", enabled: p.indexOf("::") !== 0, action: () => Shell.openProperties(p) }
                                ], g.x, g.y)
                                return
                            }
                            if (m.x >= row.indent - 2 && m.x < row.indent + 14 && row.modelData.expandable)
                                ex.toggleNode(p)
                            else if (p === "::favorites")
                                ex.toggleNode(p)
                            else
                                ex.navigate(p, true)
                        }
                        onDoubleClicked: if (row.modelData.expandable) ex.toggleNode(row.modelData.path)
                    }
                    // Expander: hollow when collapsed, filled when open; fades in while hovering the pane
                    Canvas {
                        visible: !row.gap && row.modelData.expandable === true
                        x: row.indent + 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 9; height: 9
                        opacity: navHover.containsMouse ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 250 } }
                        property bool isOpen: row.modelData.open === true
                        property bool hot: expMouse.containsMouse
                        onIsOpenChanged: requestPaint()
                        onHotChanged: requestPaint()
                        onPaint: {
                            const c = getContext("2d")
                            c.reset()
                            c.lineWidth = 1
                            c.beginPath()
                            if (isOpen) {
                                c.moveTo(7.5, 1.5); c.lineTo(7.5, 7.5); c.lineTo(1.5, 7.5)
                                c.closePath()
                                c.fillStyle = hot ? Theme.c("#1c97ea") : Theme.c("#595959")
                                c.strokeStyle = hot ? Theme.c("#1c97ea") : Theme.c("#262626")
                            } else {
                                c.moveTo(2.5, 0.5); c.lineTo(6.5, 4.5); c.lineTo(2.5, 8.5)
                                c.closePath()
                                c.fillStyle = Theme.c("white")
                                c.strokeStyle = hot ? Theme.c("#1c97ea") : Theme.c("#a6a6a6")
                            }
                            c.fill(); c.stroke()
                        }
                        MouseArea { id: expMouse; anchors.fill: parent; anchors.margins: -3; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                    }
                    AppIcon {
                        visible: !row.gap
                        x: row.indent + 14
                        anchors.verticalCenter: parent.verticalCenter
                        size: 16
                        name: row.modelData.icon || ""
                    }
                    VText {
                        visible: !row.gap
                        x: row.indent + 35
                        width: parent.width - x - 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.name || ""
                        elide: Text.ElideRight
                        color: (row.modelData.depth || 0) === 0 && row.modelData.expandable ? ex.headingBlue : Theme.text
                    }
                }
                ScrollIndicator7 { flickable: tree }
            }
        }
        // Splitter
        Rectangle {
            visible: ex.navPaneShown
            x: navPane.width - 1
            width: 1; height: parent.height
            color: Theme.c("#d6e5f5")
            MouseArea {
                x: -3; width: 7; height: parent.height
                cursorShape: Qt.SplitHCursor
                property real startX: 0
                onPressed: (m) => startX = m.x
                onPositionChanged: (m) => { if (pressed) ex.navWidth = Math.max(120, Math.min(body.width * 0.5, ex.navWidth + m.x - startX)) }
            }
        }

        // ---- Content
        Rectangle {
            id: contentArea
            x: navPane.width
            width: parent.width - x - previewPane.width
            height: parent.height
            color: Theme.c("white")
            clip: true

            // Library header
            Item {
                id: libHeader
                visible: ex.library !== null && ex.library.path === ex.location && !ex.searchMode
                width: parent.width
                height: visible ? 56 : 0
                VText { x: 14; y: 8; text: ex.library ? ex.library.name + " library" : ""; color: ex.headingBlue; font.pixelSize: 17 }
                Row {
                    x: 14; y: 33
                    VText { text: "Includes: "; color: Theme.textMuted }
                    VText { text: "1 location"; color: ex.linkBlue }
                }
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    y: 12
                    spacing: 4
                    VText { text: "Arrange by:"; color: Theme.textMuted }
                    Item {
                        id: arrange
                        width: arrText.implicitWidth + 14; height: arrText.implicitHeight
                        VText { id: arrText; text: "Folder"; color: ex.linkBlue }
                        Chevron { x: arrText.implicitWidth + 4; anchors.verticalCenter: parent.verticalCenter; color: ex.linkBlue }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ex.popupAt(arrange, ex.sortEntries()) }
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom; x: 10; width: parent.width - 20; height: 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.c("#d5e0ee") }
                        GradientStop { position: 1; color: Theme.c("#ffffff") }
                    }
                }
            }

            Item {
                id: viewArea
                y: libHeader.height
                width: parent.width
                height: parent.height - y

                // Dropping on empty space moves files into this folder
                DropArea {
                    anchors.fill: parent
                    enabled: !ex.virtualView
                    keys: ["vitrum-files"]
                    onEntered: (d) => {
                        const src = d.source
                        if (!ex.canDropOn(ex.location, src) || src.paths.every(p => Files.parentDir(p) === ex.location))
                            d.accepted = false
                    }
                    onDropped: (d) => { if (ex.dropOn(ex.location, d.source)) d.accept() }
                }

                // Rubber-band selection on empty space
                MouseArea {
                    id: band
                    anchors.fill: parent
                    enabled: !ex.virtualView
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    property point start: Qt.point(0, 0)
                    property rect r: Qt.rect(0, 0, 0, 0)
                    property bool dragging: false
                    property var base: ({})
                    function offset() { return ex.gridMode ? 4 : detailsHeader.height }
                    onPressed: (m) => {
                        ex.forceActiveFocus()
                        ex.renaming = ""
                        if (m.button === Qt.RightButton) {
                            ex.selected = {}
                            const g = mapToItem(Shell.root, m.x, m.y)
                            ex.backgroundMenu(g.x, g.y)
                            return
                        }
                        const v = ex.activeView()
                        start = Qt.point(m.x + v.contentX, m.y + v.contentY - offset())
                        base = (m.modifiers & Qt.ControlModifier) ? Object.assign({}, ex.selected) : {}
                        if (!(m.modifiers & Qt.ControlModifier))
                            ex.selected = {}
                        dragging = false
                    }
                    onPositionChanged: (m) => {
                        if (!pressed) return
                        const v = ex.activeView()
                        const px = m.x + v.contentX, py = m.y + v.contentY - offset()
                        if (!dragging && Math.abs(px - start.x) + Math.abs(py - start.y) < 4) return
                        dragging = true
                        r = Qt.rect(Math.min(start.x, px), Math.min(start.y, py), Math.abs(px - start.x), Math.abs(py - start.y))
                        const s = Object.assign({}, base)
                        for (let i = 0; i < dir.count; ++i) {
                            const ir = ex.itemRect(i)
                            if (ir.x < r.x + r.width && ir.x + ir.width > r.x && ir.y < r.y + r.height && ir.y + ir.height > r.y)
                                s[dir.pathAt(i)] = true
                        }
                        ex.selected = s
                        // Scroll while dragging past the edges
                        if (m.y > height - 10) v.contentY = Math.min(Math.max(0, v.contentHeight - v.height), v.contentY + 12)
                        else if (m.y < 10) v.contentY = Math.max(0, v.contentY - 12)
                    }
                    onReleased: dragging = false
                }

                // Icons, list and tiles
                GridView {
                    id: grid
                    visible: ex.gridMode && !ex.virtualView
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.topMargin: 4
                    cellWidth: ex.spec.w
                    cellHeight: ex.spec.h
                    flow: ex.viewMode === "list" ? GridView.FlowTopToBottom : GridView.FlowLeftToRight
                    model: visible ? dir : null
                    clip: true
                    interactive: false
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: GridItem {}
                    ScrollIndicator7 { flickable: grid }
                    WheelHandler {
                        onWheel: (w) => {
                            if (grid.flow === GridView.FlowTopToBottom)
                                grid.contentX = Math.max(0, Math.min(grid.contentWidth - grid.width, grid.contentX - w.angleDelta.y))
                            else
                                grid.contentY = Math.max(0, Math.min(grid.contentHeight - grid.height, grid.contentY - w.angleDelta.y))
                        }
                    }
                }

                // Details and Content
                Item {
                    visible: !ex.gridMode && !ex.virtualView
                    anchors.fill: parent
                    Rectangle {
                        id: detailsHeader
                        visible: ex.viewMode === "details"
                        x: -list.contentX
                        width: Math.max(parent.width, list.contentWidth)
                        height: visible ? 25 : 0
                        color: Theme.c("white")
                        z: 2
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.c("#e5e5e5") }
                        Row {
                            x: 6
                            height: parent.height
                            HeaderCell { title: "Name"; key: "name"; w: ex.colName; onResized: (d) => ex.colName = Math.max(60, ex.colName + d) }
                            HeaderCell { visible: ex.searchMode; title: "Folder"; key: ""; w: ex.colFolder; onResized: (d) => ex.colFolder = Math.max(60, ex.colFolder + d) }
                            HeaderCell { title: "Date modified"; key: "modified"; w: ex.colDate; onResized: (d) => ex.colDate = Math.max(60, ex.colDate + d) }
                            HeaderCell { title: "Type"; key: "type"; w: ex.colType; onResized: (d) => ex.colType = Math.max(50, ex.colType + d) }
                            HeaderCell { title: "Size"; key: "size"; w: ex.colSize; alignRight: true; onResized: (d) => ex.colSize = Math.max(40, ex.colSize + d) }
                        }
                    }
                    ListView {
                        id: list
                        y: detailsHeader.height
                        width: parent.width
                        height: parent.height - y
                        model: !ex.gridMode && !ex.virtualView ? dir : null
                        clip: true
                        interactive: false
                        contentWidth: ex.viewMode === "details" ? 6 + ex.colName + (ex.searchMode ? ex.colFolder : 0) + ex.colDate + ex.colType + ex.colSize + 10 : width
                        flickableDirection: Flickable.HorizontalAndVerticalFlick
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: RowItem {}
                        ScrollIndicator7 { flickable: list }
                        WheelHandler {
                            onWheel: (w) => {
                                list.contentY = Math.max(0, Math.min(list.contentHeight - list.height, list.contentY - w.angleDelta.y))
                                if (w.angleDelta.x !== 0)
                                    list.contentX = Math.max(0, Math.min(list.contentWidth - list.width, list.contentX - w.angleDelta.x))
                            }
                        }
                    }
                }

                // Rubber band
                Rectangle {
                    visible: band.dragging
                    x: band.r.x - ex.activeView().contentX + (ex.gridMode ? 4 : 0)
                    y: band.r.y - ex.activeView().contentY + band.offset()
                    width: band.r.width
                    height: band.r.height
                    color: Qt.rgba(0.2, 0.6, 1, 0.22)
                    border.color: Theme.c("#3399ff")
                }

                VText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: (ex.gridMode ? 14 : detailsHeader.height + 14)
                    visible: !ex.virtualView && dir.count === 0 && !dir.searching
                    text: ex.searchMode ? "No items match your search." : "This folder is empty."
                    color: Theme.c("#6d6d6d")
                }

                // Computer and Libraries
                Flickable {
                    id: virtualFlick
                    visible: ex.virtualView
                    anchors.fill: parent
                    contentHeight: virtualCol.height + 20
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    MouseArea {
                        width: virtualFlick.width; height: Math.max(virtualFlick.height, virtualCol.height + 20)
                        onPressed: { ex.forceActiveFocus(); ex.selected = {} }
                    }
                    Column {
                        id: virtualCol
                        x: 12; y: 8
                        width: parent.width - 24
                        spacing: 4
                        readonly property var vols: { ex.treeRev; return ex.computerView ? ex.drives() : [] }
                        readonly property var fixed: vols.filter(v => !v.removable && !v.other)
                        readonly property var removable: vols.filter(v => v.removable && !v.other)
                        readonly property var other: vols.filter(v => v.other === true)
                        GroupHeader { visible: ex.computerView; text: "Hard Disk Drives (" + virtualCol.fixed.length + ")" }
                        Flow {
                            visible: ex.computerView
                            width: parent.width
                            spacing: 6
                            Repeater { model: virtualCol.fixed; delegate: DriveTile {} }
                        }
                        GroupHeader { visible: ex.computerView && virtualCol.removable.length > 0; text: "Devices with Removable Storage (" + virtualCol.removable.length + ")" }
                        Flow {
                            visible: ex.computerView && virtualCol.removable.length > 0
                            width: parent.width
                            spacing: 6
                            Repeater { model: virtualCol.removable; delegate: DriveTile {} }
                        }
                        GroupHeader { visible: ex.computerView && virtualCol.other.length > 0; text: "Other (" + virtualCol.other.length + ")" }
                        Flow {
                            visible: ex.computerView && virtualCol.other.length > 0
                            width: parent.width
                            spacing: 6
                            Repeater { model: virtualCol.other; delegate: DriveTile {} }
                        }
                        VText { visible: ex.librariesView; text: "Libraries"; color: ex.headingBlue; font.pixelSize: 17; height: 30 }
                        VText { visible: ex.librariesView; text: "Open a library to see your files and arrange them by folder, date, and other properties."; color: Theme.textMuted; width: parent.width; wrapMode: Text.Wrap }
                        Item { visible: ex.librariesView; width: 1; height: 8 }
                        Flow {
                            visible: ex.librariesView
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: ex.librariesView ? ex.libraries : []
                                delegate: Tile {
                                    required property var modelData
                                    tilePath: modelData.path
                                    iconSource: Theme.icon(modelData.icon)
                                    line1: modelData.name
                                    line2: "Library"
                                }
                            }
                        }
                    }
                    ScrollIndicator7 { flickable: virtualFlick }
                }
            }
        }

        // ---- Preview pane
        Rectangle {
            id: previewPane
            visible: ex.previewPaneShown
            anchors.right: parent.right
            width: visible ? ex.previewWidth : 0
            height: parent.height
            color: Theme.c("white")
            Rectangle { width: 1; height: parent.height; color: Theme.c("#d6e5f5") }
            MouseArea {
                x: -3; width: 7; height: parent.height
                cursorShape: Qt.SplitHCursor
                property real startX: 0
                onPressed: (m) => startX = m.x
                onPositionChanged: (m) => { if (pressed) ex.previewWidth = Math.max(160, Math.min(body.width * 0.5, ex.previewWidth - (m.x - startX))) }
            }
            readonly property var sel: ex.selectedPaths()
            readonly property string file: visible && sel.length === 1 && !Files.isDir(sel[0]) ? sel[0] : ""
            readonly property bool isImg: file.length > 0 && Files.isImage(file)
            readonly property bool isTxt: file.length > 0 && !isImg && Files.isText(file)
            Image {
                visible: previewPane.isImg
                anchors.fill: parent
                anchors.margins: 16
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize: Qt.size(600, 600)
                source: previewPane.isImg ? Files.toUrl(previewPane.file) : ""
            }
            Flickable {
                visible: previewPane.isTxt
                anchors.fill: parent
                anchors.margins: 10
                contentHeight: previewText.height
                clip: true
                Text {
                    id: previewText
                    width: parent.width
                    wrapMode: Text.WrapAnywhere
                    font.family: "monospace"
                    font.pixelSize: 11
                    text: previewPane.isTxt ? Files.readText(previewPane.file).substring(0, 6000) : ""
                }
            }
            VText {
                visible: !previewPane.isImg && !previewPane.isTxt
                anchors.centerIn: parent
                text: previewPane.file.length ? "No preview available." : "Select a file to preview."
                color: Theme.c("#6d6d6d")
            }
        }
    }

    // ---- Details pane
    Rectangle {
        id: detailsPane
        visible: ex.detailsPaneShown
        anchors.bottom: statusBar.top
        width: parent.width
        height: visible ? 66 : 0
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.c("#fafcfe") }
            GradientStop { position: 1; color: Theme.c("#e3ecf7") }
        }
        Rectangle { width: parent.width; height: 1; color: Theme.c("#c5d4e6") }
        readonly property var sel: ex.selectedPaths()
        readonly property var vol: ex.computerView && sel.length === 1 ? ex.drives().find(v => v.path === sel[0]) : undefined
        readonly property var info: visible && sel.length === 1 && !vol && !ex.virtualView ? Files.info(sel[0]) : null
        readonly property bool isImg: info !== null && Files.isImage(sel[0])
        readonly property var props: {
            if (info) {
                const p = [["Date modified:", info.modifiedShort]]
                if (!Files.isDir(sel[0])) p.push(["Size:", info.size])
                p.push(["Date created:", info.createdShort])
                return p
            }
            if (vol) return [["Space used:", ""], ["Total size:", Files.formatSize(vol.total)], ["Space free:", Files.formatSize(vol.free)]]
            if (sel.length > 1) {
                let total = 0
                sel.forEach(s => { const i = dir.indexOf(s); if (i >= 0) total += dir.get(i).size })
                return [["Size:", Files.formatSize(total)]]
            }
            if (ex.computerView) return [["Workgroup:", "WORKGROUP"], ["Processor:", Sys.cpuModel], ["Memory:", Sys.memoryTotal]]
            return []
        }
        Item {
            x: 14
            width: 48; height: 48
            anchors.verticalCenter: parent.verticalCenter
            AppIcon {
                anchors.centerIn: parent
                size: 48
                visible: !detailsPane.isImg
                name: detailsPane.vol ? Theme.icon("drive")
                     : detailsPane.info ? ex.fileIcon(detailsPane.info.icon, Files.isDir(detailsPane.sel[0]), detailsPane.sel[0])
                     : detailsPane.sel.length > 1 ? Theme.icon("file-generic")
                     : ex.folderIcon(ex.location)
            }
            Image {
                anchors.fill: parent
                visible: detailsPane.isImg
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize: Qt.size(96, 96)
                source: visible ? Files.toUrl(detailsPane.sel[0]) : ""
            }
        }
        Column {
            x: 74
            width: 210
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            VText {
                width: parent.width
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSize + 2
                text: detailsPane.vol ? detailsPane.vol.name
                      : detailsPane.info ? detailsPane.info.name
                      : detailsPane.sel.length > 1 ? detailsPane.sel.length + " items selected"
                      : ex.computerView ? Sys.hostName.toUpperCase()
                      : ex.librariesView ? "4 items"
                      : (ex.searchMode ? dir.count + " items" : dir.count + (dir.count === 1 ? " item" : " items"))
            }
            VText {
                width: parent.width
                elide: Text.ElideRight
                color: Theme.textMuted
                text: detailsPane.vol ? (detailsPane.vol.removable ? "Removable Disk" : "Local Disk")
                      : detailsPane.info ? detailsPane.info.type
                      : ex.computerView ? "Computer" : ""
            }
        }
        Grid {
            x: 296
            anchors.verticalCenter: parent.verticalCenter
            columns: 2
            columnSpacing: 6
            rowSpacing: 2
            Repeater {
                model: detailsPane.props.length * 2
                delegate: Item {
                    required property int index
                    readonly property var pair: detailsPane.props[Math.floor(index / 2)] || ["", ""]
                    readonly property bool isLabel: index % 2 === 0
                    readonly property bool isBar: pair[0] === "Space used:" && !isLabel
                    width: isLabel ? 92 : Math.max(120, detailsPane.width - 296 - 110)
                    height: 16
                    VText {
                        visible: !parent.isBar
                        anchors.right: parent.isLabel ? parent.right : undefined
                        width: parent.isLabel ? implicitWidth : parent.width
                        elide: Text.ElideRight
                        text: parent.isLabel ? parent.pair[0] : parent.pair[1]
                        color: parent.isLabel ? Theme.c("#5a6779") : Theme.c("#1e1e1e")
                    }
                    UsageBar {
                        visible: parent.isBar
                        width: 140; height: 12; y: 2
                        total: detailsPane.vol ? detailsPane.vol.total : 0
                        free: detailsPane.vol ? detailsPane.vol.free : 0
                    }
                }
            }
        }
    }

    // ---- Status bar
    Rectangle {
        id: statusBar
        visible: ex.statusBarShown
        anchors.bottom: parent.bottom
        width: parent.width
        height: visible ? 22 : 0
        color: Theme.c("#f0f0f0")
        Rectangle { width: parent.width; height: 1; color: Theme.c("#d0d0d0") }
        VText {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            text: {
                const n = ex.selectedPaths().length
                return (ex.virtualView ? "" : dir.count + " items") + (n > 0 ? "    " + n + " selected" : "")
            }
        }
    }

    // ================================================================ parts
    component HeaderCell: Item {
        id: hc
        property string title: ""
        property string key: ""
        property real w: 100
        property bool alignRight: false
        signal resized(real delta)
        width: visible ? w : 0
        height: 25
        readonly property bool sorted: key.length > 0 && dir.sortField === key
        Rectangle {
            anchors.fill: parent
            visible: hcMouse.containsMouse
            border.color: Theme.c("#c0d8ef")
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.c("#f7fbff") }
                GradientStop { position: 1; color: Theme.c("#e3effc") }
            }
        }
        Chevron {
            visible: hc.sorted
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            color: Theme.c("#7a8ea6")
            rotation: dir.sortDescending ? 0 : 180
        }
        VText {
            x: 6
            width: parent.width - 12
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: hc.alignRight ? Text.AlignRight : Text.AlignLeft
            text: hc.title
            color: Theme.c("#4c607a")
            elide: Text.ElideRight
        }
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height - 8; y: 4; color: Theme.c("#e5e5e5") }
        MouseArea {
            id: hcMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (hc.key.length === 0) return
                if (dir.sortField === hc.key) dir.sortDescending = !dir.sortDescending
                else { dir.sortField = hc.key; dir.sortDescending = hc.key === "modified" }
            }
        }
        MouseArea {
            anchors.right: parent.right
            anchors.rightMargin: -4
            width: 8; height: parent.height
            cursorShape: Qt.SplitHCursor
            property real startX: 0
            onPressed: (m) => startX = m.x
            onPositionChanged: (m) => { if (pressed) hc.resized(m.x - startX) }
        }
    }

    component GroupHeader: Item {
        id: gh
        property string text: ""
        width: parent ? parent.width : 0
        height: visible ? 28 : 0
        VText { id: ghText; y: 6; text: gh.text; color: ex.headingBlue; font.pixelSize: Theme.fontSize + 1 }
        Rectangle {
            x: ghText.implicitWidth + 8
            y: ghText.y + Math.round(ghText.implicitHeight / 2)
            width: Math.max(0, parent.width - x)
            height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Theme.c("#b6c8e0") }
                GradientStop { position: 1; color: Theme.c("#ffffff") }
            }
        }
    }

    component UsageBar: Rectangle {
        id: ub
        property real total: 0
        property real free: 0
        readonly property real used: total > 0 ? 1 - free / total : 0
        readonly property bool full: used > 0.9
        border.color: Theme.c("#bcbcbc")
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.c("#f2f2f2") }
            GradientStop { position: 1; color: Theme.c("#e2e2e2") }
        }
        Rectangle {
            x: 1; y: 1
            height: parent.height - 2
            width: Math.max(0, (parent.width - 2) * ub.used)
            gradient: Gradient {
                GradientStop { position: 0; color: ub.full ? Theme.c("#ff8c7a") : Theme.c("#68c3f5") }
                GradientStop { position: 0.5; color: ub.full ? Theme.c("#e2442d") : Theme.c("#2b9ce8") }
                GradientStop { position: 1; color: ub.full ? Theme.c("#c9311c") : Theme.c("#1c87d6") }
            }
        }
    }

    component SelectionBack: Rectangle {
        id: sb
        property bool sel: false
        property bool hot: false
        readonly property bool act: ex.frame ? ex.frame.active : true
        radius: 3
        visible: sel || hot
        border.color: Theme.c(sel ? (act ? (hot ? "#7da2ce" : "#84acdd") : "#d9d9d9") : "#b8d6fb")
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.c(sb.sel ? (sb.act ? (sb.hot ? "#dcebfc" : "#e2eefc") : "#f8f8f8") : "#fafbfd") }
            GradientStop { position: 1; color: Theme.c(sb.sel ? (sb.act ? (sb.hot ? "#c1dcfc" : "#c6dff9") : "#e5e5e5") : "#ebf3fd") }
        }
        Rectangle { anchors.fill: parent; anchors.margins: 1; radius: 2; color: "transparent"; border.color: Qt.rgba(1, 1, 1, 0.55) }
    }

    // Shared mouse handling for items
    function itemPressed(index, filePath, m, item) {
        ex.forceActiveFocus()
        renaming = ""
        pressPos = item.mapToItem(Shell.root, m.x, m.y)
        if (m.button === Qt.RightButton) {
            if (!selected[filePath]) { selectOnly(filePath); anchor = index }
            current = index
            const g = item.mapToItem(Shell.root, m.x, m.y)
            itemMenu(filePath, g.x, g.y)
            return
        }
        if (m.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))
            selectIndex(index, m.modifiers)
        else if (!selected[filePath]) {
            selectOnly(filePath); anchor = index; current = index
        } else
            current = index
    }
    function itemRect(i) {
        if (gridMode) {
            if (viewMode === "list") {
                const rows = Math.max(1, Math.floor(grid.height / spec.h))
                return Qt.rect(Math.floor(i / rows) * spec.w, (i % rows) * spec.h, spec.w - 8, spec.h)
            }
            const cols = Math.max(1, Math.floor(grid.width / spec.w))
            return Qt.rect((i % cols) * spec.w, Math.floor(i / cols) * spec.h, spec.w - 4, spec.h - 4)
        }
        const rh = viewMode === "content" ? 62 : 22
        return Qt.rect(0, i * rh, viewMode === "details" ? colName : list.width, rh)
    }

    component RenameField: TextField7 {
        id: rf
        property string target: ""
        property string original: ""
        property bool isDir: false
        visible: ex.renaming.length > 0 && ex.renaming === target
        height: 22
        onVisibleChanged: if (visible) {
            text = original
            input.forceActiveFocus()
            const dot = original.lastIndexOf(".")
            input.select(0, isDir || dot <= 0 ? original.length : dot)
        }
        onAccepted: { if (text !== original && text.length) Files.rename(target, text); ex.renaming = ""; ex.forceActiveFocus() }
        Keys.onEscapePressed: { ex.renaming = ""; ex.forceActiveFocus() }
    }

    component GridItem: Item {
        id: gi
        required property int index
        required property string name
        required property string fileName
        required property string filePath
        required property bool isDir
        required property string sizeText
        required property string type
        required property string icon
        required property bool isImage
        required property bool hidden
        readonly property bool big: ex.spec.icon >= 48 && ex.viewMode !== "tiles"
        readonly property bool tiles: ex.viewMode === "tiles"
        readonly property int iconSize: ex.spec.icon
        readonly property bool sel: ex.selected[filePath] === true
        readonly property bool thumbnail: isImage && iconSize >= 48
        width: ex.spec.w - (ex.viewMode === "list" ? 8 : 4)
        height: ex.spec.h - (big ? 4 : 0)
        property int iconRev: 0
        Connections { target: Compat; function onIconReady(exe, url) { if (exe === gi.filePath) gi.iconRev++ } }
        SelectionBack { anchors.fill: parent; anchors.margins: 1; sel: gi.sel || giDrop.containsDrag; hot: giMouse.containsMouse && !ex.dragging }
        Rectangle {
            visible: ex.current === gi.index && ex.activeFocus && !gi.sel
            anchors.fill: parent; anchors.margins: 1; radius: 3
            color: "transparent"; border.color: Theme.c("#a8c6ea")
        }
        Item {
            id: iconBox
            x: gi.big ? (parent.width - width) / 2 : 4
            y: gi.big ? 4 : (parent.height - height) / 2
            width: gi.iconSize; height: gi.iconSize
            opacity: (Files.clipboardCut && Files.clipboard.indexOf(gi.filePath) >= 0) || gi.hidden ? 0.5 : 1
            AppIcon {
                anchors.fill: parent
                size: gi.iconSize
                visible: !gi.thumbnail
                name: { gi.iconRev; return ex.fileIcon(gi.icon, gi.isDir, gi.filePath) }
                fallback: "text-x-generic"
            }
            // Thumbnails for pictures, framed like photos
            Rectangle {
                visible: gi.thumbnail && thumb.status === Image.Ready
                anchors.centerIn: parent
                width: thumb.paintedWidth + 6; height: thumb.paintedHeight + 6
                color: Theme.c("white")
                border.color: Theme.c("#c9d1db")
            }
            Image {
                id: thumb
                visible: gi.thumbnail
                anchors.fill: parent
                anchors.margins: 4
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize: Qt.size(gi.iconSize * 2, gi.iconSize * 2)
                source: gi.thumbnail ? Files.toUrl(gi.filePath) : ""
            }
        }
        Column {
            visible: ex.renaming !== gi.filePath
            x: gi.big ? 2 : iconBox.x + iconBox.width + (gi.tiles ? 8 : 5)
            y: gi.big ? iconBox.y + iconBox.height + 4 : (gi.tiles ? (parent.height - height) / 2 : 0)
            width: gi.big ? parent.width - 4 : parent.width - x - 4
            VText {
                width: parent.width
                height: gi.big ? (gi.sel ? 64 : 32) : (gi.tiles ? 16 : gi.height)
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: gi.big ? Text.AlignHCenter : Text.AlignLeft
                text: gi.name
                wrapMode: gi.big ? Text.Wrap : Text.NoWrap
                maximumLineCount: gi.big ? (gi.sel ? 4 : 2) : 1
                elide: Text.ElideRight
            }
            VText { visible: gi.tiles; width: parent.width; text: gi.type; color: Theme.textMuted; elide: Text.ElideRight }
            VText { visible: gi.tiles && !gi.isDir; width: parent.width; text: gi.sizeText; color: Theme.textMuted; elide: Text.ElideRight }
        }
        MouseArea {
            id: giMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            onPressed: (m) => ex.itemPressed(gi.index, gi.filePath, m, giMouse)
            onPositionChanged: (m) => { if (pressed && (m.buttons & Qt.LeftButton)) ex.dragMove(gi.filePath, giMouse, m) }
            onReleased: ex.dragEnd()
            onDoubleClicked: (m) => { if (m.button === Qt.LeftButton) ex.open(gi.filePath) }
        }
        DropArea {
            id: giDrop
            anchors.fill: parent
            enabled: gi.isDir
            keys: ["vitrum-files"]
            onEntered: (d) => { if (!ex.canDropOn(gi.filePath, d.source)) d.accepted = false }
            onDropped: (d) => { if (ex.dropOn(gi.filePath, d.source)) d.accept() }
        }
        RenameField {
            target: gi.filePath
            original: gi.fileName
            isDir: gi.isDir
            x: gi.big ? -2 : iconBox.x + iconBox.width + 3
            y: gi.big ? iconBox.y + iconBox.height + 2 : (parent.height - height) / 2
            width: gi.big ? parent.width + 4 : 200
        }
    }

    component RowItem: Item {
        id: ri
        required property int index
        required property string name
        required property string fileName
        required property string filePath
        required property bool isDir
        required property string sizeText
        required property string modifiedText
        required property string type
        required property string icon
        required property bool isImage
        required property bool hidden
        required property string location
        readonly property bool content: ex.viewMode === "content"
        width: Math.max(list.width, list.contentWidth)
        height: content ? 62 : 22
        readonly property bool sel: ex.selected[filePath] === true
        property int iconRev: 0
        Connections { target: Compat; function onIconReady(exe, url) { if (exe === ri.filePath) ri.iconRev++ } }
        SelectionBack {
            x: ri.content ? 2 : 4
            width: ri.content ? parent.width - 4 : 6 + ex.colName + (ex.searchMode ? ex.colFolder : 0) + ex.colDate + ex.colType + ex.colSize - 4
            height: parent.height - 1
            sel: ri.sel || riDrop.containsDrag
            hot: riMouse.containsMouse && !ex.dragging
        }
        Rectangle { visible: ri.content; anchors.bottom: parent.bottom; x: 6; width: parent.width - 12; height: 1; color: Theme.c("#e8edf3") }
        AppIcon {
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            size: ri.content ? 48 : 16
            visible: !(ri.content && ri.isImage)
            opacity: (Files.clipboardCut && Files.clipboard.indexOf(ri.filePath) >= 0) || ri.hidden ? 0.5 : 1
            name: { ri.iconRev; return ex.fileIcon(ri.icon, ri.isDir, ri.filePath) }
            fallback: "text-x-generic"
        }
        Image {
            visible: ri.content && ri.isImage
            x: 10; width: 48; height: 48
            anchors.verticalCenter: parent.verticalCenter
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            sourceSize: Qt.size(96, 96)
            source: visible ? Files.toUrl(ri.filePath) : ""
        }
        // Details columns
        Row {
            visible: !ri.content && ex.renaming !== ri.filePath
            x: 6 + 26
            height: parent.height
            VText { width: ex.colName - 30; height: parent.height; verticalAlignment: Text.AlignVCenter; text: ri.name; elide: Text.ElideRight }
            Item { width: 4; height: 1 }
            VText { visible: ex.searchMode; width: ex.colFolder; height: parent.height; leftPadding: 6; verticalAlignment: Text.AlignVCenter; text: ri.location; color: Theme.c("#6d6d6d"); elide: Text.ElideMiddle }
            VText { width: ex.colDate; height: parent.height; leftPadding: 6; verticalAlignment: Text.AlignVCenter; text: ri.modifiedText; color: Theme.c("#6d6d6d"); elide: Text.ElideRight }
            VText { width: ex.colType; height: parent.height; leftPadding: 6; verticalAlignment: Text.AlignVCenter; text: ri.type; color: Theme.c("#6d6d6d"); elide: Text.ElideRight }
            VText { width: ex.colSize; height: parent.height; rightPadding: 8; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; text: ri.sizeText; color: Theme.c("#6d6d6d") }
        }
        // Content layout
        Column {
            visible: ri.content && ex.renaming !== ri.filePath
            x: 70
            width: Math.max(120, parent.width * 0.5 - 70)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            VText { width: parent.width; text: ri.name; font.pixelSize: Theme.fontSize + 1; elide: Text.ElideRight }
            VText { width: parent.width; text: ex.searchMode ? ri.location : ri.type; color: Theme.c("#6d6d6d"); elide: Text.ElideMiddle }
        }
        Column {
            visible: ri.content
            x: parent.width * 0.55
            width: parent.width * 0.45 - 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            VText { width: parent.width; text: "Date modified: " + ri.modifiedText; color: Theme.c("#6d6d6d"); elide: Text.ElideRight }
            VText { visible: !ri.isDir; width: parent.width; text: "Size: " + ri.sizeText; color: Theme.c("#6d6d6d") }
        }
        MouseArea {
            id: riMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            preventStealing: true
            onPressed: (m) => ex.itemPressed(ri.index, ri.filePath, m, riMouse)
            onPositionChanged: (m) => { if (pressed && (m.buttons & Qt.LeftButton)) ex.dragMove(ri.filePath, riMouse, m) }
            onReleased: ex.dragEnd()
            onDoubleClicked: (m) => { if (m.button === Qt.LeftButton) ex.open(ri.filePath) }
        }
        DropArea {
            id: riDrop
            anchors.fill: parent
            enabled: ri.isDir
            keys: ["vitrum-files"]
            onEntered: (d) => { if (!ex.canDropOn(ri.filePath, d.source)) d.accepted = false }
            onDropped: (d) => { if (ex.dropOn(ri.filePath, d.source)) d.accept() }
        }
        RenameField {
            target: ri.filePath
            original: ri.fileName
            isDir: ri.isDir
            x: ri.content ? 66 : 30
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(300, ex.colName)
        }
    }

    component Tile: Item {
        id: tile
        property string tilePath: ""
        property string iconSource: ""
        property string line1: ""
        property string line2: ""
        property bool showBar: false
        property real barTotal: 0
        property real barFree: 0
        width: 262; height: 62
        readonly property bool sel: ex.selected[tilePath] === true
        SelectionBack { anchors.fill: parent; sel: tile.sel; hot: tileMouse.containsMouse }
        AppIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; size: 48; name: tile.iconSource }
        Column {
            x: 60
            width: parent.width - 66
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            VText { width: parent.width; text: tile.line1; elide: Text.ElideRight }
            UsageBar { visible: tile.showBar; width: 180; height: 14; total: tile.barTotal; free: tile.barFree }
            VText { width: parent.width; text: tile.line2; color: Theme.textMuted; elide: Text.ElideRight }
        }
        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: (m) => {
                ex.forceActiveFocus()
                ex.selectOnly(tile.tilePath)
                if (m.button === Qt.RightButton) {
                    const g = mapToItem(Shell.root, m.x, m.y)
                    Shell.showMenu([
                        { text: "Open", bold: true, action: () => ex.navigate(tile.tilePath, true) },
                        { text: "Open in new window", action: () => Shell.openExplorer(tile.tilePath) },
                        { separator: true },
                        { text: "Properties", action: () => Shell.openProperties(tile.tilePath) }
                    ], g.x, g.y)
                }
            }
            onDoubleClicked: ex.navigate(tile.tilePath, true)
        }
    }

    component DriveTile: Tile {
        required property var modelData
        tilePath: modelData.path
        iconSource: modelData.other ? Theme.icon("folder") : Theme.icon("drive")
        line1: modelData.name
        line2: modelData.total > 0 ? Files.formatSize(modelData.free) + " free of " + Files.formatSize(modelData.total) : "Programs installed for Windows"
        showBar: modelData.total > 0
        barTotal: modelData.total
        barFree: modelData.free
    }
}
