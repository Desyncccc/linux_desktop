import QtQuick
import Qt.labs.folderlistmodel
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// File Explorer: glass navigation bar, command bar, navigation pane,
// icon/details views and a details pane.
FocusScope {
    id: ex
    property var frame: null
    property string path: ""
    readonly property string location: path.length > 0 ? path : Files.home
    readonly property bool computerView: location === "::computer"
    property var history: []
    property int historyIndex: -1
    property string viewMode: "icons"   // "icons" | "details"
    property string filter: ""
    property var selected: ({})
    property string renaming: ""
    property bool showHidden: false

    Component.onCompleted: navigate(location, true)
    // Use `path` itself here: the derived `location` binding may not have
    // re-evaluated yet when this handler runs.
    onPathChanged: {
        const target = path.length > 0 ? path : Files.home
        if (history[historyIndex] !== target)
            navigate(target, true)
    }

    function titleFor(p) {
        if (p === "::computer") return "Computer"
        if (p === Files.trash) return "Recycle Bin"
        if (p === Files.home) return Sys.realName
        if (p === "/") return "Local Disk (/)"
        return Files.fileName(p)
    }
    function navigate(p, push) {
        if (p !== "::computer" && !Files.isDir(p))
            return
        selected = {}
        renaming = ""
        filter = ""
        searchField.text = ""
        if (push) {
            const h = history.slice(0, historyIndex + 1)
            h.push(p)
            history = h
            historyIndex = h.length - 1
        }
        if (path !== p)
            path = p
        if (frame) {
            frame.internalTitle = titleFor(p)
            frame.internalIcon = p === "::computer" ? Theme.icon("computer") : p === Files.trash ? Theme.icon("trash-empty") : Theme.icon("folder")
        }
        ex.forceActiveFocus()
    }
    function back() { if (historyIndex > 0) { historyIndex--; navigate(history[historyIndex], false) } }
    function forward() { if (historyIndex < history.length - 1) { historyIndex++; navigate(history[historyIndex], false) } }
    function up() { if (!computerView && location !== "/") navigate(Files.parentDir(location), true); else if (location === "/") navigate("::computer", true) }

    function open(p) {
        if (Files.isDir(p))
            navigate(p, true)
        else
            Shell.openFile(p)
    }
    function selectedPaths() { return Object.keys(selected).filter(k => selected[k]) }
    function selectOnly(p) { const s = {}; if (p) s[p] = true; selected = s }

    function itemMenu(p, gx, gy) {
        if (!selected[p])
            selectOnly(p)
        const isDir = Files.isDir(p)
        const entries = [
            { text: "Open", bold: true, action: () => ex.open(p) }
        ]
        if (Compat.isCompatFile(p))
            entries.push({ text: "Run", icon: Theme.icon("exe"), action: () => Shell.openFile(p) })
        if (Apps.isProgramFile(p)) {
            entries.push({ text: "Pin to taskbar", icon: Theme.icon("pin"), action: () => { const id = Apps.ensureEntryForFile(p); if (id) Prefs.pin(id) } })
            entries.push({ text: "Pin to Start menu", action: () => { const id = Apps.ensureEntryForFile(p); if (id) Prefs.pinToStart(id) } })
        }
        if (!isDir && Files.isText(p))
            entries.push({ text: "Edit", action: () => Shell.openInternal("notepad", { path: p }) })
        if (isDir)
            entries.push({ text: "Open in new window", action: () => Shell.openExplorer(p) })
        entries.push({ text: "Open terminal here", icon: Theme.icon("terminal"), action: () => Launcher.openTerminal(isDir ? p : Files.parentDir(p)) })
        entries.push({ separator: true })
        entries.push({ text: "Cut", action: () => Files.cut(ex.selectedPaths()) })
        entries.push({ text: "Copy", action: () => Files.copy(ex.selectedPaths()) })
        if (isDir)
            entries.push({ text: "Paste", enabled: Files.clipboard.length > 0, action: () => Files.paste(p) })
        entries.push({ separator: true })
        entries.push({ text: "Delete", action: () => Files.moveToTrash(ex.selectedPaths()) })
        entries.push({ text: "Rename", action: () => ex.renaming = p })
        entries.push({ separator: true })
        entries.push({ text: "Properties", action: () => Shell.openProperties(p) })
        Shell.showMenu(entries, gx, gy)
    }
    function backgroundMenu(gx, gy) {
        if (computerView)
            return
        Shell.showMenu([
            { text: "View: Large icons", checked: ex.viewMode === "icons", action: () => ex.viewMode = "icons" },
            { text: "View: Details", checked: ex.viewMode === "details", action: () => ex.viewMode = "details" },
            { text: "Show hidden files", checked: ex.showHidden, action: () => ex.showHidden = !ex.showHidden },
            { separator: true },
            { text: "Refresh", action: () => { const p = ex.location; folder.folder = ""; folder.folder = Files.toUrl(p) } },
            { text: "Paste", enabled: Files.clipboard.length > 0, action: () => Files.paste(ex.location) },
            { separator: true },
            { text: "New folder", icon: Theme.icon("folder"), action: () => { const p = Files.makeFolder(ex.location); if (p) { ex.selectOnly(p); ex.renaming = p } } },
            { text: "New text document", icon: "text-x-generic", action: () => { const p = Files.makeFile(ex.location); if (p) { ex.selectOnly(p); ex.renaming = p } } },
            { separator: true },
            { text: "Open terminal here", icon: Theme.icon("terminal"), action: () => Launcher.openTerminal(ex.location) },
            { text: "Properties", action: () => Shell.openProperties(ex.location) }
        ], gx, gy)
    }

    FolderListModel {
        id: folder
        folder: ex.computerView ? "" : Files.toUrl(ex.location)
        showDirsFirst: true
        showHidden: ex.showHidden
        showDotAndDotDot: false
        sortCaseSensitive: false
        nameFilters: ex.filter.length > 0 ? ["*" + ex.filter + "*"] : []
    }

    Keys.onPressed: (e) => {
        const ctrl = e.modifiers & Qt.ControlModifier
        if (e.key === Qt.Key_Backspace || (e.key === Qt.Key_Left && (e.modifiers & Qt.AltModifier))) { back(); e.accepted = true }
        else if (e.key === Qt.Key_Right && (e.modifiers & Qt.AltModifier)) { forward(); e.accepted = true }
        else if (e.key === Qt.Key_Up && (e.modifiers & Qt.AltModifier)) { up(); e.accepted = true }
        else if (e.key === Qt.Key_Delete) { Files.moveToTrash(selectedPaths()); e.accepted = true }
        else if (e.key === Qt.Key_F2) { const s = selectedPaths(); if (s.length === 1) renaming = s[0]; e.accepted = true }
        else if (e.key === Qt.Key_F5) { folder.folder = ""; folder.folder = Files.toUrl(location); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { selectedPaths().forEach(p => open(p)); e.accepted = true }
        else if (ctrl && e.key === Qt.Key_C) { Files.copy(selectedPaths()); e.accepted = true }
        else if (ctrl && e.key === Qt.Key_X) { Files.cut(selectedPaths()); e.accepted = true }
        else if (ctrl && e.key === Qt.Key_V) { Files.paste(location); e.accepted = true }
        else if (ctrl && e.key === Qt.Key_A) { const s = {}; for (let i = 0; i < folder.count; ++i) s[folder.get(i, "filePath")] = true; selected = s; e.accepted = true }
        else if (ctrl && e.key === Qt.Key_N) { Shell.openExplorer(location); e.accepted = true }
        else if (ctrl && e.key === Qt.Key_F) { searchField.input.forceActiveFocus(); e.accepted = true }
        else if (ctrl && e.key === Qt.Key_L) { address.editing = true; e.accepted = true }
    }

    // ---- Glass navigation bar (frame extended into the client area)
    Item {
        id: navBar
        width: parent.width
        height: 38
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
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.28) }
            }
        }

        component NavButton: Item {
            id: nb
            property string iconName: ""
            property bool on: true
            signal activated()
            width: 26; height: 26
            Rectangle {
                anchors.fill: parent
                radius: 13
                opacity: nb.on ? 1 : 0.45
                border.color: "#1d3f73"
                gradient: Gradient {
                    GradientStop { position: 0; color: nbMouse.containsMouse && nb.on ? "#bfe4ff" : "#9ccaf0" }
                    GradientStop { position: 0.5; color: nbMouse.containsMouse && nb.on ? "#4ea3ef" : "#3d7fc8" }
                    GradientStop { position: 1; color: nbMouse.containsMouse && nb.on ? "#7cc6ff" : "#2f68ad" }
                }
                Rectangle { anchors.fill: parent; anchors.margins: 1; radius: 12; color: "transparent"; border.color: Qt.rgba(1, 1, 1, 0.5) }
                Image { anchors.centerIn: parent; width: 14; height: 14; sourceSize: Qt.size(28, 28); source: nb.iconName }
            }
            MouseArea { id: nbMouse; anchors.fill: parent; hoverEnabled: true; onClicked: if (nb.on) nb.activated() }
        }
        Row {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            NavButton { iconName: Theme.icon("arrow-left"); on: ex.historyIndex > 0; onActivated: ex.back() }
            NavButton { iconName: Theme.icon("arrow-right"); on: ex.historyIndex < ex.history.length - 1; onActivated: ex.forward() }
            NavButton { iconName: Theme.icon("arrow-up"); on: !ex.computerView; onActivated: ex.up() }
        }

        // Breadcrumb address bar
        Rectangle {
            id: address
            property bool editing: false
            x: 96
            width: parent.width - x - searchField.width - 16
            height: 24
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(1, 1, 1, 0.92)
            border.color: Qt.rgba(0, 0, 0, 0.45)
            radius: 2
            onEditingChanged: if (editing) { addrInput.text = ex.computerView ? "" : ex.location; addrInput.forceActiveFocus(); addrInput.selectAll() }
            AppIcon { x: 4; anchors.verticalCenter: parent.verticalCenter; size: 16; name: ex.computerView ? Theme.icon("computer") : Theme.icon("folder") }
            Row {
                visible: !address.editing
                x: 24
                height: parent.height
                clip: true
                width: parent.width - 30
                Repeater {
                    model: {
                        if (ex.computerView) return [{ name: "Computer", path: "::computer" }]
                        const parts = ex.location.split("/").filter(s => s.length)
                        const crumbs = [{ name: "Computer", path: "::computer" }, { name: "Local Disk", path: "/" }]
                        let acc = ""
                        for (let i = 0; i < parts.length; ++i) {
                            acc += "/" + parts[i]
                            crumbs.push({ name: acc === Files.home ? Sys.realName : parts[i], path: acc })
                        }
                        return crumbs.length > 6 ? crumbs.slice(crumbs.length - 6) : crumbs
                    }
                    delegate: Row {
                        required property var modelData
                        height: address.height
                        HoverItem {
                            width: crumbText.implicitWidth + 10; height: parent.height - 2; y: 1
                            radius: 1
                            VText { id: crumbText; anchors.centerIn: parent; text: modelData.name }
                            onClicked: ex.navigate(modelData.path, true)
                        }
                        VText { text: "›"; color: Theme.textMuted; anchors.verticalCenter: parent.verticalCenter; width: 10; horizontalAlignment: Text.AlignHCenter }
                    }
                }
            }
            MouseArea {
                visible: !address.editing
                anchors.fill: parent
                z: -1
                onClicked: address.editing = true
            }
            TextInput {
                id: addrInput
                visible: address.editing
                x: 24
                width: parent.width - 30
                height: parent.height
                verticalAlignment: TextInput.AlignVCenter
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                selectByMouse: true
                clip: true
                onAccepted: {
                    const t = text.replace(/^~/, Files.home)
                    address.editing = false
                    if (Files.isDir(t)) ex.navigate(t, true)
                    else if (Files.exists(t)) Shell.openFile(t)
                    else Launcher.runCommand(text)
                }
                onActiveFocusChanged: if (!activeFocus) address.editing = false
                Keys.onEscapePressed: address.editing = false
            }
        }
        TextField7 {
            id: searchField
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(220, parent.width * 0.25)
            height: 24
            placeholder: "Search " + ex.titleFor(ex.location)
            iconName: Theme.icon("search")
            onTextChanged: ex.filter = text
        }
    }

    // ---- Command bar
    Rectangle {
        id: commandBar
        y: navBar.height
        width: parent.width
        height: 30
        gradient: Gradient {
            GradientStop { position: 0; color: "#f5faff" }
            GradientStop { position: 0.5; color: "#e5eefa" }
            GradientStop { position: 0.51; color: "#d9e6f6" }
            GradientStop { position: 1; color: "#dce8f7" }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#a0afc3" }
        component Cmd: HoverItem {
            id: cmd
            property string text: ""
            property string iconName: ""
            width: cmdRow.implicitWidth + 14
            height: 24
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            Row {
                id: cmdRow
                anchors.centerIn: parent
                spacing: 4
                AppIcon { visible: cmd.iconName.length > 0; size: 16; name: cmd.iconName; anchors.verticalCenter: parent.verticalCenter }
                VText { text: cmd.text; color: "#1e395b"; anchors.verticalCenter: parent.verticalCenter }
            }
        }
        Row {
            x: 6
            height: parent.height
            spacing: 2
            Cmd {
                text: "Organize ▾"
                onClicked: {
                    const g = mapToItem(Shell.root, 0, height)
                    Shell.showMenu([
                        { text: "Cut", action: () => Files.cut(ex.selectedPaths()) },
                        { text: "Copy", action: () => Files.copy(ex.selectedPaths()) },
                        { text: "Paste", enabled: Files.clipboard.length > 0, action: () => Files.paste(ex.location) },
                        { separator: true },
                        { text: "Select all", action: () => { const s = {}; for (let i = 0; i < folder.count; ++i) s[folder.get(i, "filePath")] = true; ex.selected = s } },
                        { separator: true },
                        { text: "Delete", action: () => Files.moveToTrash(ex.selectedPaths()) },
                        { text: "Rename", enabled: ex.selectedPaths().length === 1, action: () => ex.renaming = ex.selectedPaths()[0] },
                        { text: "Properties", action: () => Shell.openProperties(ex.selectedPaths()[0] || ex.location) },
                        { separator: true },
                        { text: "Close", action: () => ex.frame.close() }
                    ], g.x, g.y)
                }
            }
            Cmd { visible: ex.selectedPaths().length > 0; text: "Open"; onClicked: ex.selectedPaths().forEach(p => ex.open(p)) }
            Cmd { visible: !ex.computerView && ex.location !== Files.trash; text: "New folder"; onClicked: { const p = Files.makeFolder(ex.location); if (p) { ex.selectOnly(p); ex.renaming = p } } }
            Cmd { visible: ex.location === Files.trash; text: "Empty the Recycle Bin"; onClicked: Files.emptyTrash() }
            Cmd { visible: ex.selectedPaths().length > 0 && ex.location !== Files.trash; text: "Delete"; onClicked: Files.moveToTrash(ex.selectedPaths()) }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 6
            height: parent.height
            Cmd { text: ex.viewMode === "icons" ? "Details" : "Icons"; iconName: Theme.icon("apps"); onClicked: ex.viewMode = ex.viewMode === "icons" ? "details" : "icons" }
        }
    }

    // ---- Navigation pane
    Rectangle {
        id: navPane
        y: commandBar.y + commandBar.height
        width: 190
        height: details.y - y
        color: "#ffffff"
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#d6e5f5" }
        Flickable {
            anchors.fill: parent
            anchors.topMargin: 6
            contentHeight: navCol.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: navCol
                width: parent.width - 4
                component NavHeader: VText { x: 8; height: 26; verticalAlignment: Text.AlignVCenter; color: "#1e3287"; font.bold: false; font.pixelSize: Theme.fontSize + 1 }
                component NavItem: HoverItem {
                    id: ni
                    property string text: ""
                    property string iconName: ""
                    property string target: ""
                    width: navCol.width
                    height: 22
                    selected: ex.location === target
                    AppIcon { x: 22; anchors.verticalCenter: parent.verticalCenter; size: 16; name: ni.iconName }
                    VText { x: 44; width: parent.width - 48; anchors.verticalCenter: parent.verticalCenter; text: ni.text }
                    onClicked: ex.navigate(ni.target, true)
                }
                NavHeader { text: "Favorites" }
                NavItem { text: "Desktop"; iconName: Theme.icon("desktop-folder"); target: Files.desktop }
                NavItem { text: "Downloads"; iconName: Theme.icon("folder-downloads"); target: Files.downloads }
                NavItem { text: Sys.realName; iconName: Theme.icon("user-home"); target: Files.home }
                Item { width: 1; height: 8 }
                NavHeader { text: "Libraries" }
                NavItem { text: "Documents"; iconName: Theme.icon("folder-documents"); target: Files.documents }
                NavItem { text: "Music"; iconName: Theme.icon("folder-music"); target: Files.music }
                NavItem { text: "Pictures"; iconName: Theme.icon("folder-pictures"); target: Files.pictures }
                NavItem { text: "Videos"; iconName: Theme.icon("folder-videos"); target: Files.videos }
                Item { width: 1; height: 8 }
                NavItem { text: "Computer"; iconName: Theme.icon("computer"); target: "::computer"; x: -14 }
                Repeater {
                    model: Files.volumes()
                    NavItem {
                        required property var modelData
                        text: modelData.name; iconName: Theme.icon("drive"); target: modelData.path
                    }
                }
                NavItem { visible: Compat.windowsAvailable; text: "Windows (C:)"; iconName: Theme.icon("drive"); target: Compat.prefix + "/drive_c" }
                Item { width: 1; height: 8 }
                NavItem { text: "Recycle Bin"; iconName: Theme.icon("trash-empty"); target: Files.trash; x: -14 }
            }
        }
    }

    // ---- Content
    Rectangle {
        id: contentArea
        x: navPane.width
        y: navPane.y
        width: parent.width - x
        height: navPane.height
        color: "white"
        clip: true

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: (m) => {
                ex.forceActiveFocus()
                ex.selectOnly("")
                ex.renaming = ""
                if (m.button === Qt.RightButton) {
                    const g = mapToItem(Shell.root, m.x, m.y)
                    ex.backgroundMenu(g.x, g.y)
                }
            }
        }

        // Computer view: drives with usage bars
        Flow {
            visible: ex.computerView
            x: 16; y: 12
            width: parent.width - 32
            spacing: 12
            VText { width: parent.width; text: "Hard Disk Drives"; color: "#1e3287"; font.pixelSize: Theme.fontSizeLarge }
            Repeater {
                model: ex.computerView ? Files.volumes().concat(Compat.windowsAvailable ? [{ name: "Windows (C:)", path: Compat.prefix + "/drive_c", total: 0, free: 0 }] : []) : []
                delegate: HoverItem {
                    id: drive
                    required property var modelData
                    width: 250; height: 58
                    AppIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; size: 40; name: Theme.icon("drive") }
                    Column {
                        x: 54; y: 6
                        width: parent.width - 60
                        spacing: 3
                        VText { text: drive.modelData.name + (drive.modelData.path !== "/" && drive.modelData.name.indexOf("(") < 0 ? " (" + drive.modelData.path + ")" : ""); width: parent.width }
                        Rectangle {
                            visible: drive.modelData.total > 0
                            width: parent.width; height: 13
                            border.color: "#9a9a9a"
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#f0f0f0" }
                                GradientStop { position: 1; color: "#dadada" }
                            }
                            Rectangle {
                                readonly property real used: drive.modelData.total > 0 ? 1 - drive.modelData.free / drive.modelData.total : 0
                                x: 1; y: 1
                                height: parent.height - 2
                                width: (parent.width - 2) * used
                                gradient: Gradient {
                                    GradientStop { position: 0; color: parent.children[0] && used > 0.9 ? "#f08a7a" : "#7ec0f0" }
                                    GradientStop { position: 1; color: used > 0.9 ? "#d9442b" : "#2f7fd0" }
                                }
                            }
                        }
                        VText {
                            visible: drive.modelData.total > 0
                            text: Files.formatSize(drive.modelData.free) + " free of " + Files.formatSize(drive.modelData.total)
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeSmall
                        }
                    }
                    onDoubleClicked: ex.navigate(drive.modelData.path, true)
                    onClicked: ex.selectOnly("")
                }
            }
            Item { width: parent.width; height: 6 }
            VText { width: parent.width; text: "Places"; color: "#1e3287"; font.pixelSize: Theme.fontSizeLarge }
            Repeater {
                model: ex.computerView ? [
                    { name: "Documents", path: Files.documents, icon: "folder-documents" },
                    { name: "Downloads", path: Files.downloads, icon: "folder-downloads" },
                    { name: "Music", path: Files.music, icon: "folder-music" },
                    { name: "Pictures", path: Files.pictures, icon: "folder-pictures" },
                    { name: "Videos", path: Files.videos, icon: "folder-videos" },
                    { name: "Desktop", path: Files.desktop, icon: "desktop-folder" }
                ] : []
                delegate: HoverItem {
                    id: placeItem
                    required property var modelData
                    width: 160; height: 44
                    AppIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; size: 32; name: Theme.icon(placeItem.modelData.icon) }
                    VText { x: 44; anchors.verticalCenter: parent.verticalCenter; text: placeItem.modelData.name }
                    onDoubleClicked: ex.navigate(modelData.path, true)
                }
            }
        }

        // Large icons
        GridView {
            id: grid
            visible: !ex.computerView && ex.viewMode === "icons"
            anchors.fill: parent
            anchors.margins: 6
            cellWidth: 96
            cellHeight: 100
            model: ex.computerView ? null : folder
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            delegate: FileItem { width: grid.cellWidth - 4; height: grid.cellHeight - 4; large: true }
            ScrollIndicator7 { flickable: grid }
        }

        // Details
        Item {
            visible: !ex.computerView && ex.viewMode === "details"
            anchors.fill: parent
            Rectangle {
                id: header
                width: parent.width; height: 24
                color: "white"
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#e5e5e5" }
                Row {
                    x: 28
                    height: parent.height
                    component Col: VText { height: parent.height; verticalAlignment: Text.AlignVCenter; color: "#4c607a"; leftPadding: 4
                        Rectangle { anchors.right: parent.right; width: 1; height: parent.height - 6; y: 3; color: "#e5e5e5" } }
                    Col { text: "Name"; width: Math.max(200, contentArea.width - 28 - 150 - 140 - 90 - 20) }
                    Col { text: "Date modified"; width: 150 }
                    Col { text: "Type"; width: 140 }
                    Col { text: "Size"; width: 90 }
                }
            }
            ListView {
                id: list
                y: header.height
                width: parent.width
                height: parent.height - y
                clip: true
                model: ex.computerView || ex.viewMode !== "details" ? null : folder
                boundsBehavior: Flickable.StopAtBounds
                delegate: FileItem { width: list.width; height: 24; large: false }
                ScrollIndicator7 { flickable: list }
            }
        }

        VText {
            anchors.centerIn: parent
            visible: !ex.computerView && folder.status === FolderListModel.Ready && folder.count === 0
            text: ex.filter.length ? "No items match your search." : "This folder is empty."
            color: Theme.textMuted
        }
    }

    // ---- Details pane
    Rectangle {
        id: details
        anchors.bottom: parent.bottom
        width: parent.width
        height: 56
        gradient: Gradient {
            GradientStop { position: 0; color: "#f8fbfe" }
            GradientStop { position: 1; color: "#e2ecf8" }
        }
        Rectangle { width: parent.width; height: 1; color: "#c5d4e6" }
        readonly property var sel: ex.selectedPaths()
        readonly property var info: sel.length === 1 ? Files.info(sel[0]) : null
        AppIcon {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            size: 40
            name: details.info ? Theme.themeIcon(details.info.icon, "text-x-generic")
                               : ex.computerView ? Theme.icon("computer") : Theme.icon("folder")
        }
        Column {
            x: 66
            anchors.verticalCenter: parent.verticalCenter
            VText {
                text: details.info ? details.info.name : details.sel.length > 1 ? details.sel.length + " items selected"
                      : ex.computerView ? Sys.hostName : folder.count + " items"
                font.pixelSize: Theme.fontSize + 1
            }
            VText {
                text: details.info ? details.info.type + (details.info.size && !Files.isDir(details.sel[0]) ? "   Size: " + details.info.size : "") + "   Modified: " + details.info.modified
                      : ex.computerView ? Sys.cpuModel + "   Memory: " + Sys.memoryTotal : ""
                color: Theme.textMuted
            }
        }
    }

    // File item used by both views
    component FileItem: Item {
        id: fi
        required property string filePath
        required property string fileName
        required property bool fileIsDir
        required property var fileModified
        required property var fileSize
        property bool large: true
        readonly property bool sel: ex.selected[filePath] === true
        property int iconRev: 0
        readonly property string icon: {
            iconRev
            if (fileIsDir) return Theme.icon("folder")
            if (Files.isImage(filePath) && large) return "file://" + filePath
            return Theme.themeIcon(Files.iconName(filePath), "text-x-generic")
        }
        Connections {
            target: Compat
            function onIconReady(exe, url) { if (exe === fi.filePath) fi.iconRev++ }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 3
            visible: fi.sel || fiMouse.containsMouse
            border.color: fi.sel ? "#7da2ce" : "#b8d6fb"
            gradient: Gradient {
                GradientStop { position: 0; color: fi.sel ? "#dcebfc" : "#fafbfd" }
                GradientStop { position: 1; color: fi.sel ? "#c1dcfc" : "#ebf3fd" }
            }
        }
        AppIcon {
            id: fiIcon
            x: fi.large ? (parent.width - width) / 2 : 6
            y: fi.large ? 6 : (parent.height - height) / 2
            size: fi.large ? 48 : 16
            name: fi.icon
            fallback: "text-x-generic"
            opacity: Files.clipboardCut && Files.clipboard.indexOf(fi.filePath) >= 0 ? 0.5 : 1
        }
        VText {
            visible: ex.renaming !== fi.filePath
            x: fi.large ? 2 : 28
            y: fi.large ? 58 : 0
            width: fi.large ? parent.width - 4 : Math.max(200, contentArea.width - 28 - 150 - 140 - 90 - 20) - 4
            height: fi.large ? undefined : parent.height
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: fi.large ? Text.AlignHCenter : Text.AlignLeft
            text: fi.fileName.endsWith(".desktop") ? Files.displayName(fi.filePath) : fi.fileName
            wrapMode: fi.large ? Text.Wrap : Text.NoWrap
            maximumLineCount: fi.large ? 2 : 1
        }
        Row {
            visible: !fi.large
            x: 28 + Math.max(200, contentArea.width - 28 - 150 - 140 - 90 - 20)
            height: parent.height
            VText { width: 150; height: parent.height; verticalAlignment: Text.AlignVCenter; leftPadding: 4; color: Theme.textMuted; text: Qt.formatDateTime(fi.fileModified, "yyyy-MM-dd hh:mm") }
            VText { width: 140; height: parent.height; verticalAlignment: Text.AlignVCenter; leftPadding: 4; color: Theme.textMuted; text: Files.typeName(fi.filePath) }
            VText { width: 90; height: parent.height; verticalAlignment: Text.AlignVCenter; leftPadding: 4; color: Theme.textMuted; text: fi.fileIsDir ? "" : Files.formatSize(fi.fileSize); horizontalAlignment: Text.AlignRight; rightPadding: 8 }
        }
        MouseArea {
            id: fiMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: (m) => {
                ex.forceActiveFocus()
                if (m.modifiers & Qt.ControlModifier) {
                    const s = Object.assign({}, ex.selected)
                    s[fi.filePath] = !s[fi.filePath]
                    ex.selected = s
                } else if (!fi.sel) {
                    ex.selectOnly(fi.filePath)
                }
                if (m.button === Qt.RightButton) {
                    const g = mapToItem(Shell.root, m.x, m.y)
                    ex.itemMenu(fi.filePath, g.x, g.y)
                }
            }
            onDoubleClicked: (m) => { if (m.button === Qt.LeftButton) ex.open(fi.filePath) }
        }
        TextField7 {
            visible: ex.renaming === fi.filePath
            x: fi.large ? -4 : 26
            y: fi.large ? 58 : 1
            width: fi.large ? parent.width + 8 : 260
            height: 22
            onVisibleChanged: if (visible) { text = fi.fileName; input.forceActiveFocus(); input.select(0, fi.fileIsDir || fi.fileName.lastIndexOf(".") <= 0 ? fi.fileName.length : fi.fileName.lastIndexOf(".")) }
            onAccepted: { if (text !== fi.fileName) Files.rename(fi.filePath, text); ex.renaming = ""; ex.forceActiveFocus() }
            Keys.onEscapePressed: { ex.renaming = ""; ex.forceActiveFocus() }
        }
    }
}
