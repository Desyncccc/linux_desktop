import QtQuick
import Vitrum
import Vitrum.Core

// The glass taskbar: start orb, combined task buttons, notification area,
// clock and the "show desktop" strip at the far right.
Item {
    id: bar
    height: Theme.taskbarHeight

    readonly property var groups: {
        Shell.revision
        const pinned = Prefs.pinnedApps
        const out = []
        const index = {}
        for (let i = 0; i < pinned.length; ++i) {
            const id = pinned[i]
            if (!Apps.get(id).name)
                continue
            const g = { key: id, desktopId: id, pinned: true, windows: [] }
            index[id] = g
            out.push(g)
        }
        const wins = Shell.windows
        for (let i = 0; i < wins.length; ++i) {
            const w = wins[i]
            if (w.closing)
                continue
            let g = index[w.groupKey]
            if (g && (Prefs.combineButtons || g.windows.length === 0)) {
                g.windows.push(w)
                continue
            }
            const key = Prefs.combineButtons ? w.groupKey : w.groupKey + "#" + w.uid
            g = { key: key, desktopId: w.desktopId, pinned: false, windows: [w] }
            index[key] = g
            out.push(g)
        }
        return out
    }
    function groupByKey(key) {
        for (let i = 0; i < groups.length; ++i)
            if (groups[i].key === key)
                return groups[i]
        return null
    }
    function activateIndex(i) {
        if (i < 0 || i >= buttons.count)
            return
        buttons.itemAt(i).activateOrMinimize()
    }

    // Glass body
    GlassSurface {
        anchors.fill: parent
        role: "panel"
        tint: Theme.taskbarTint
        intensity: Theme.taskbarIntensity
        brightness: 0.0
        streaks: 0.35
    }
    Rectangle {
        anchors.fill: parent
        visible: !Theme.isModern
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.20) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.06) }
            GradientStop { position: 0.51; color: Qt.rgba(0, 0, 0, 0.05) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.10) }
        }
    }
    Rectangle { width: parent.width; height: 1; color: Theme.isModern ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.7) }
    Rectangle { visible: !Theme.isModern; y: 1; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.35) }

    // Swallow clicks on empty taskbar space; right-click for the taskbar menu.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: (m) => {
            Shell.closePopups()
            if (m.button === Qt.RightButton) {
                const g = mapToItem(Shell.root, m.x, m.y)
                Shell.showMenu([
                    { text: "Task Manager", icon: Theme.icon("taskmanager"), action: () => Shell.openTaskManager() },
                    { separator: true },
                    { text: "Show the desktop", action: () => Shell.toggleDesktop() },
                    { text: "Center taskbar icons", checked: Prefs.taskbarCentered, action: () => Prefs.taskbarCentered = !Prefs.taskbarCentered },
                    { text: "Use small icons", checked: Prefs.smallTaskbarIcons, action: () => Prefs.smallTaskbarIcons = !Prefs.smallTaskbarIcons },
                    { separator: true },
                    { text: "Taskbar settings", icon: Theme.icon("settings"), action: () => Shell.openSettings("taskbar") }
                ], g.x, g.y - 190)
            }
        }
    }

    // Start orb + task buttons (left aligned, or centred as a group)
    Row {
        id: tasks
        x: Prefs.taskbarCentered ? Math.max(2, Math.round((bar.width - width) / 2)) : 2
        height: parent.height
        spacing: 1
        Behavior on x { enabled: Prefs.animations; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        StartOrb { id: orb }
        Repeater {
            id: buttons
            model: bar.groups
            delegate: TaskButton {
                required property var modelData
                required property int index
                group: modelData
                // eslint-disable-next-line
                Component.onCompleted: {}
            }
        }
    }

    // Notification area
    Row {
        id: tray
        anchors.right: desktopStrip.left
        anchors.rightMargin: 2
        height: parent.height
        spacing: 0

        component TrayButton: Item {
            id: tb
            property string iconSource: ""
            property bool held: false
            property string tip: ""
            signal activated()
            width: 26
            height: bar.height
            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                anchors.topMargin: 5
                radius: 2
                visible: tbMouse.containsMouse || tb.held
                color: Qt.rgba(1, 1, 1, tb.held ? 0.22 : 0.14)
                border.color: Qt.rgba(1, 1, 1, 0.3)
            }
            Image {
                anchors.centerIn: parent
                source: tb.iconSource
                width: 16; height: 16
                sourceSize: Qt.size(32, 32)
            }
            MouseArea {
                id: tbMouse
                anchors.fill: parent
                hoverEnabled: true
                onPressed: tb.activated()
            }
            ToolTip7 { target: tbMouse; text: tb.tip }
        }

        TrayButton {
            iconSource: Sys.networkType === "wifi" ? Theme.icon(Sys.wifiEnabled ? "net-wifi" : "net-wifi-off")
                        : Sys.networkType === "wired" ? Theme.icon("net-wired") : Theme.icon("net-none")
            held: Shell.flyout === "network"
            tip: Sys.networkType === "none" ? "Not connected" : (Sys.networkName || (Sys.networkType === "wifi" ? "Wireless network" : "Network")) + "\nInternet access"
            onActivated: { const g = mapToItem(Shell.root, width / 2, 0); Shell.flyoutX = g.x; Shell.toggleFlyout("network") }
        }
        TrayButton {
            iconSource: Theme.icon(Sys.muted || Sys.volume === 0 ? "volume-muted" : "volume")
            held: Shell.flyout === "volume"
            tip: Sys.hasAudio ? "Speakers: " + Sys.volume + "%" + (Sys.muted ? " (muted)" : "") : "No audio device"
            onActivated: { const g = mapToItem(Shell.root, width / 2, 0); Shell.flyoutX = g.x; Shell.toggleFlyout("volume") }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: (w) => Sys.setVolume(Sys.volume + (w.angleDelta.y > 0 ? 5 : -5))
            }
        }
        Item {
            visible: Sys.hasBattery
            width: visible ? 30 : 0
            height: bar.height
            Rectangle {
                id: batt
                anchors.centerIn: parent
                width: 20; height: 10
                radius: 2
                color: "transparent"
                border.color: "white"
                border.width: 1.4
                Rectangle {
                    x: 2; y: 2
                    height: parent.height - 4
                    width: (parent.width - 4) * Sys.batteryLevel / 100
                    color: Sys.batteryLevel < 15 ? "#ff5a4a" : Sys.charging ? "#7cf07c" : "white"
                }
                Rectangle { anchors.left: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 2; height: 5; color: "white" }
            }
            MouseArea { id: battMouse; anchors.fill: parent; hoverEnabled: true }
            ToolTip7 { target: battMouse; text: Sys.batteryLevel + "% " + (Sys.charging ? "available (plugged in, charging)" : "remaining") }
        }

        // Clock
        Item {
            id: clock
            width: Math.max(timeText.implicitWidth, dateText.implicitWidth) + 18
            height: bar.height
            property date now: new Date()
            Timer {
                interval: Prefs.showSeconds ? 1000 : 5000
                running: true
                repeat: true
                triggeredOnStart: true
                onTriggered: clock.now = new Date()
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                radius: 2
                visible: clockMouse.containsMouse || Shell.flyout === "clock"
                color: Qt.rgba(1, 1, 1, Shell.flyout === "clock" ? 0.22 : 0.14)
                border.color: Qt.rgba(1, 1, 1, 0.3)
            }
            Column {
                anchors.centerIn: parent
                spacing: Prefs.smallTaskbarIcons ? 0 : 1
                Text {
                    id: timeText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(clock.now, Prefs.clock24h ? (Prefs.showSeconds ? "HH:mm:ss" : "HH:mm") : (Prefs.showSeconds ? "h:mm:ss AP" : "h:mm AP"))
                    color: "white"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }
                Text {
                    id: dateText
                    visible: !Prefs.smallTaskbarIcons
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(clock.now, Qt.locale().dateFormat(Locale.ShortFormat))
                    color: "white"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    renderType: Text.NativeRendering
                }
            }
            MouseArea {
                id: clockMouse
                anchors.fill: parent
                hoverEnabled: true
                onPressed: { const g = mapToItem(Shell.root, width / 2, 0); Shell.flyoutX = g.x; Shell.toggleFlyout("clock") }
            }
            ToolTip7 { target: clockMouse; text: Qt.formatDate(clock.now, "dddd, MMMM d, yyyy") }
        }

        TrayButton {
            iconSource: Theme.icon(Notifications.count > 0 ? "notification-new" : "notification")
            held: Shell.actionCenterOpen
            tip: Notifications.count > 0 ? Notifications.count + " new notification" + (Notifications.count > 1 ? "s" : "") : "No new notifications"
            onActivated: Shell.toggleActionCenter()
        }
    }

    // Show desktop / Aero Peek strip
    Item {
        id: desktopStrip
        anchors.right: parent.right
        width: 14
        height: parent.height
        Rectangle { width: 1; height: parent.height; color: Qt.rgba(0, 0, 0, 0.45) }
        Rectangle { x: 1; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.25) }
        Rectangle {
            x: 2
            width: parent.width - 2
            height: parent.height
            visible: stripMouse.containsMouse
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.45) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.15) }
            }
        }
        Timer {
            interval: 500
            running: stripMouse.containsMouse && !stripMouse.pressed
            onTriggered: Shell.peekDesktop = true
        }
        MouseArea {
            id: stripMouse
            anchors.fill: parent
            hoverEnabled: true
            onExited: Shell.peekDesktop = false
            onClicked: { Shell.peekDesktop = false; Shell.closePopups(); Shell.toggleDesktop() }
        }
        ToolTip7 { target: stripMouse; text: "Show desktop" }
    }
}
