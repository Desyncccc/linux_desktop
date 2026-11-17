import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// Two-column start menu: programs + search on the left (light pane),
// places and power on the right (glass).
Item {
    id: menu
    width: 412
    height: 540
    property bool open: Shell.startOpen
    property string query: search.text.trim()
    readonly property var results: query.length > 0 ? Apps.search(query, 14) : []
    readonly property var settingsResults: {
        if (query.length < 2)
            return []
        const pages = [
            { name: "Personalization", page: "personalize", keys: "wallpaper background color colour theme transparency glass accent personalize" },
            { name: "Taskbar settings", page: "taskbar", keys: "taskbar clock icons pinned center" },
            { name: "Display", page: "display", keys: "display screen brightness night light resolution" },
            { name: "Notifications", page: "notifications", keys: "notifications do not disturb toast" },
            { name: "Windows app support", page: "compat", keys: "exe windows wine bat jar compatibility programs" },
            { name: "About this PC", page: "about", keys: "about system version pc computer info" }
        ]
        const q = query.toLowerCase()
        return pages.filter(p => p.name.toLowerCase().indexOf(q) >= 0 || p.keys.indexOf(q) >= 0)
    }
    readonly property var pinned: {
        Prefs.startPinned
        const apps = Apps.appsForIds(Prefs.startPinned)
        return apps.length > 0 ? apps : Apps.appsForIds(["notepad", "calculator", "explorer", "paint"].map(k => Apps.idForInternal(k)))
    }
    readonly property var frequent: {
        Prefs.launchCountsChanged; Apps.count
        const ids = Prefs.frequentApps(10).filter(id => Prefs.startPinned.indexOf(id) < 0)
        return Apps.appsForIds(ids.slice(0, Math.max(0, 9 - pinned.length)))
    }

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.anim(130) } }
    property real slide: open ? 0 : 10
    Behavior on slide { NumberAnimation { duration: Theme.anim(150); easing.type: Easing.OutCubic } }

    x: Prefs.taskbarCentered ? Math.round((Shell.screenWidth - width) / 2) : 0
    y: Shell.screenHeight - Theme.taskbarHeight - height + slide

    onOpenChanged: {
        if (open) {
            search.text = ""
            Shell.startAllPrograms = Shell.startAllPrograms && open
            search.input.forceActiveFocus()
        }
    }

    function launch(app) {
        Shell.launchApp(app.desktopId)
    }
    function appMenu(app, gx, gy) {
        const entries = [
            { text: "Open", bold: true, action: () => menu.launch(app) },
            { separator: true },
            Prefs.isPinned(app.desktopId)
                ? { text: "Unpin from taskbar", icon: Theme.icon("pin"), action: () => Prefs.unpin(app.desktopId) }
                : { text: "Pin to taskbar", icon: Theme.icon("pin"), action: () => Prefs.pin(app.desktopId) },
            Prefs.isStartPinned(app.desktopId)
                ? { text: "Unpin from Start menu", action: () => Prefs.unpinFromStart(app.desktopId) }
                : { text: "Pin to Start menu", action: () => Prefs.pinToStart(app.desktopId) }
        ]
        Shell.showMenu(entries, gx, gy)
        Shell.startOpen = true
    }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: (m) => m.accepted = true }

    RectangularGlow {
        anchors.fill: frame
        glowRadius: 12; spread: 0.1; cornerRadius: 18
        color: "#90000000"
    }
    GlassPanel {
        id: frame
        anchors.fill: parent
        tracking: menu
        radius: 7
        intensity: Theme.transparency ? Math.min(0.9, Theme.intensity + 0.15) : 0.95
        tint: Qt.darker(Theme.accent, 1.5)
    }

    // ---- Left pane
    Rectangle {
        id: left
        x: 8; y: 10
        width: 250
        height: parent.height - 18
        radius: 4
        color: Qt.rgba(1, 1, 1, 0.97)
        border.color: Qt.rgba(0, 0, 0, 0.55)

        // Pinned + frequent
        ListView {
            id: mainList
            visible: menu.query.length === 0 && !Shell.startAllPrograms
            x: 4; y: 6
            width: parent.width - 8
            height: parent.height - 84
            clip: true
            interactive: false
            model: menu.pinned.concat(menu.pinned.length && menu.frequent.length ? [{ separator: true }] : []).concat(menu.frequent)
            delegate: Item {
                id: row
                required property var modelData
                width: mainList.width
                height: modelData.separator ? 9 : 44
                Separator { visible: !!row.modelData.separator; anchors.verticalCenter: parent.verticalCenter; x: 6; width: parent.width - 12 }
                HoverItem {
                    visible: !row.modelData.separator
                    anchors.fill: parent
                    anchors.margins: 1
                    AppIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; size: 32; name: row.modelData.iconName || "" }
                    VText {
                        x: 46; width: parent.width - 50
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.name || ""
                    }
                    onClicked: menu.launch(row.modelData)
                    onRightClicked: (x, y) => menu.appMenu(row.modelData, x, y)
                }
            }
        }

        // All programs, grouped into folders
        ListView {
            id: allList
            visible: menu.query.length === 0 && Shell.startAllPrograms
            x: 4; y: 6
            width: parent.width - 8
            height: parent.height - 84
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            property var expanded: ({})
            model: { Apps.count; return menu.open && Shell.startAllPrograms ? Apps.categoryGroups() : [] }
            delegate: Column {
                id: grp
                required property var modelData
                width: allList.width
                readonly property bool isOpen: allList.expanded[modelData.category] === true
                HoverItem {
                    width: parent.width; height: 24
                    AppIcon { x: 4; anchors.verticalCenter: parent.verticalCenter; size: 16; name: Theme.icon("folder") }
                    VText { x: 26; anchors.verticalCenter: parent.verticalCenter; text: grp.modelData.category }
                    onClicked: {
                        const e = Object.assign({}, allList.expanded)
                        e[grp.modelData.category] = !grp.isOpen
                        allList.expanded = e
                    }
                }
                Repeater {
                    model: grp.isOpen ? grp.modelData.apps : []
                    delegate: HoverItem {
                        id: progItem
                        required property var modelData
                        width: grp.width; height: 24
                        AppIcon { x: 22; anchors.verticalCenter: parent.verticalCenter; size: 16; name: progItem.modelData.iconName || "" }
                        VText { x: 44; width: parent.width - 48; anchors.verticalCenter: parent.verticalCenter; text: progItem.modelData.name }
                        onClicked: menu.launch(modelData)
                        onRightClicked: (x, y) => menu.appMenu(modelData, x, y)
                    }
                }
            }
            ScrollIndicator7 { flickable: allList }
        }

        // Search results
        Flickable {
            id: resultsView
            visible: menu.query.length > 0
            x: 4; y: 6
            width: parent.width - 8
            height: parent.height - 84
            clip: true
            contentHeight: resultsCol.height
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: resultsCol
                width: parent.width
                VText {
                    visible: menu.results.length > 0
                    x: 6; height: 22
                    verticalAlignment: Text.AlignVCenter
                    text: "Programs (" + menu.results.length + ")"
                    color: "#1e3287"
                    font.bold: true
                }
                Repeater {
                    model: menu.results
                    delegate: HoverItem {
                        id: resItem
                        required property var modelData
                        required property int index
                        width: resultsCol.width; height: 30
                        selected: index === 0
                        AppIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 24; name: resItem.modelData.iconName || "" }
                        VText { x: 40; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter; text: resItem.modelData.name }
                        onClicked: menu.launch(modelData)
                        onRightClicked: (x, y) => menu.appMenu(modelData, x, y)
                    }
                }
                VText {
                    visible: menu.settingsResults.length > 0
                    x: 6; height: 24
                    verticalAlignment: Text.AlignBottom
                    text: "Settings (" + menu.settingsResults.length + ")"
                    color: "#1e3287"
                    font.bold: true
                }
                Repeater {
                    model: menu.settingsResults
                    delegate: HoverItem {
                        id: setItem
                        required property var modelData
                        width: resultsCol.width; height: 26
                        AppIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 16; name: Theme.icon("settings") }
                        VText { x: 40; anchors.verticalCenter: parent.verticalCenter; text: setItem.modelData.name }
                        onClicked: Shell.openSettings(modelData.page)
                    }
                }
                VText {
                    visible: menu.results.length === 0 && menu.settingsResults.length === 0
                    x: 8; height: 30
                    verticalAlignment: Text.AlignVCenter
                    text: "No items match your search."
                    color: Theme.textMuted
                }
                Separator { width: parent.width; visible: menu.query.length > 0 }
                HoverItem {
                    width: resultsCol.width; height: 26
                    AppIcon { x: 12; anchors.verticalCenter: parent.verticalCenter; size: 16; name: Theme.icon("run") }
                    VText { x: 40; width: parent.width - 44; anchors.verticalCenter: parent.verticalCenter; text: "Run “" + menu.query + "”" }
                    onClicked: { Launcher.runCommand(menu.query); Shell.closePopups() }
                }
            }
        }

        Separator { x: 8; width: parent.width - 16; y: parent.height - 76 }

        HoverItem {
            x: 4; y: parent.height - 72
            width: parent.width - 8; height: 28
            VText {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: Shell.startAllPrograms || menu.query.length > 0 ? "Back" : "All Programs"
                font.bold: false
            }
            Image {
                x: Shell.startAllPrograms || menu.query.length > 0 ? 0 : parent.width - 24
                anchors.verticalCenter: parent.verticalCenter
                visible: !(Shell.startAllPrograms || menu.query.length > 0)
                source: Theme.icon("chevron-right")
                width: 14; height: 14
                layer.enabled: true
                layer.effect: ColorOverlay { color: "#2b5ea8" }
            }
            onClicked: {
                if (menu.query.length > 0)
                    search.text = ""
                else
                    Shell.startAllPrograms = !Shell.startAllPrograms
                search.input.forceActiveFocus()
            }
        }

        TextField7 {
            id: search
            x: 8; y: parent.height - 36
            width: parent.width - 16
            height: 26
            rounded: true
            placeholder: "Search programs and files"
            iconName: Theme.icon("search")
            input.color: Theme.text
            onAccepted: {
                if (menu.results.length > 0)
                    menu.launch(menu.results[0])
                else if (menu.settingsResults.length > 0)
                    Shell.openSettings(menu.settingsResults[0].page)
                else if (menu.query.length > 0) {
                    if (!Launcher.runCommand(menu.query))
                        Shell.notify("Can't find “" + menu.query + "”", "Make sure you typed the name correctly, and then try again.", "dialog-warning")
                    Shell.closePopups()
                }
            }
            Keys.onEscapePressed: Shell.toggleStart()
        }
    }

    // ---- Right column (glass)
    Column {
        id: rightCol
        x: left.x + left.width + 10
        y: 8
        width: menu.width - x - 8
        spacing: 1

        Item {
            width: parent.width; height: 84
            Rectangle {
                id: avatarFrame
                anchors.horizontalCenter: parent.horizontalCenter
                y: 4
                width: 64; height: 64
                radius: 5
                border.color: Qt.rgba(0, 0, 0, 0.6)
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.8) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.35) }
                }
                Rectangle {
                    anchors.fill: parent; anchors.margins: 4
                    radius: 3
                    clip: true
                    gradient: Gradient {
                        GradientStop { position: 0; color: "#8fc8f0" }
                        GradientStop { position: 1; color: "#2d6db5" }
                    }
                    Image {
                        anchors.fill: parent
                        visible: Sys.avatar.length > 0
                        source: Sys.avatar
                        fillMode: Image.PreserveAspectCrop
                        sourceSize: Qt.size(112, 112)
                    }
                    Image {
                        visible: Sys.avatar.length === 0
                        anchors.centerIn: parent
                        width: 40; height: 40
                        source: Theme.icon("switch-user")
                        sourceSize: Qt.size(80, 80)
                    }
                }
            }
        }

        component Link: Item {
            id: link
            property string text: ""
            property string iconName: ""
            property bool bold: false
            signal activated()
            width: rightCol.width
            height: 30
            HoverItem {
                anchors.fill: parent
                dark: true
                onClicked: link.activated()
            }
            Text {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 16
                text: link.text
                color: "white"
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: link.bold
                style: Text.Raised
                styleColor: "#a0000000"
                renderType: Text.NativeRendering
            }
        }
        component Gap: Item { width: rightCol.width; height: 8
            Rectangle { y: 4; x: 8; width: parent.width - 16; height: 1; color: Qt.rgba(1, 1, 1, 0.22) } }

        Link { text: Sys.realName; bold: true; onActivated: Shell.openExplorer(Files.home) }
        Link { text: "Documents"; onActivated: Shell.openExplorer(Files.documents) }
        Link { text: "Pictures"; onActivated: Shell.openExplorer(Files.pictures) }
        Link { text: "Music"; onActivated: Shell.openExplorer(Files.music) }
        Link { text: "Downloads"; onActivated: Shell.openExplorer(Files.downloads) }
        Gap {}
        Link { text: "Computer"; onActivated: Shell.openExplorer("::computer") }
        Link { text: "Recycle Bin"; onActivated: Shell.openExplorer(Files.trash) }
        Gap {}
        Link { text: "Settings"; onActivated: Shell.openSettings("") }
        Link { text: "Task Manager"; onActivated: Shell.openTaskManager() }
        Link { text: "Run..."; onActivated: Shell.openRun() }
    }

    // ---- Power
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: parent.height - 40
        spacing: -1
        component PowerPart: Item {
            id: pp
            property string text: ""
            property string iconName: ""
            property bool leftRound: true
            signal activated()
            width: text.length ? label.implicitWidth + 26 : 22
            height: 26
            Rectangle {
                anchors.fill: parent
                radius: 3
                border.color: Qt.rgba(0, 0, 0, 0.7)
                gradient: Gradient {
                    GradientStop { position: 0; color: ppMouse.containsMouse ? "#f7b8a8" : Qt.rgba(1, 1, 1, 0.35) }
                    GradientStop { position: 0.5; color: ppMouse.containsMouse ? "#e0533a" : Qt.rgba(1, 1, 1, 0.12) }
                    GradientStop { position: 1; color: ppMouse.containsMouse ? "#b8321c" : Qt.rgba(1, 1, 1, 0.06) }
                }
                Rectangle { anchors.fill: parent; anchors.margins: 1; radius: 2; color: "transparent"; border.color: Qt.rgba(1, 1, 1, 0.35) }
            }
            Text {
                id: label
                visible: pp.text.length > 0
                anchors.centerIn: parent
                text: pp.text
                color: "white"
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                style: Text.Raised
                styleColor: "#90000000"
                renderType: Text.NativeRendering
            }
            Image {
                visible: pp.iconName.length > 0
                anchors.centerIn: parent
                width: 12; height: 12
                source: pp.iconName
                sourceSize: Qt.size(24, 24)
            }
            MouseArea { id: ppMouse; anchors.fill: parent; hoverEnabled: true; onClicked: pp.activated() }
        }
        PowerPart {
            text: "Shut down"
            onActivated: { Shell.closePopups(); Sys.powerOff() }
        }
        PowerPart {
            iconName: Theme.icon("chevron-right")
            onActivated: {
                const g = mapToItem(Shell.root, width, height)
                Shell.showMenu([
                    { text: "Switch user", icon: Theme.icon("switch-user"), enabled: false },
                    { text: "Sign out", icon: Theme.icon("logout"), action: () => Shell.logout() },
                    { text: "Lock", icon: Theme.icon("lock"), action: () => Shell.lock() },
                    { separator: true },
                    { text: "Restart", icon: Theme.icon("restart"), action: () => Sys.reboot() },
                    { text: "Sleep", icon: Theme.icon("sleep"), action: () => Sys.suspend() },
                    { text: "Hibernate", icon: Theme.icon("sleep"), action: () => Sys.hibernate() }
                ], g.x, g.y - 160)
                Shell.startOpen = true
            }
        }
    }
}
