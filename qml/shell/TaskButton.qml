import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// One taskbar button: a pinned and/or running application group.
Item {
    id: btn
    property var group: ({ key: "", desktopId: "", pinned: false, windows: [] })
    property int index: 0
    readonly property var wins: group.windows || []
    readonly property bool running: wins.length > 0
    readonly property bool hasActive: wins.indexOf(Shell.activeWindow) >= 0
    readonly property bool hovered: ma.containsMouse
    readonly property var info: group.desktopId ? Apps.get(group.desktopId) : ({})
    readonly property string iconSource: running ? wins[0].iconSource : Theme.themeIcon(info.iconName, "application-x-executable")
    readonly property string label: running ? wins[wins.length - 1].title : (info.name || "")
    readonly property bool showLabel: !Prefs.combineButtons && running
    property bool flash: false

    width: showLabel ? 168 : Theme.taskButtonWidth
    height: Theme.taskbarHeight

    function activateOrMinimize() {
        if (!running) {
            Shell.launchApp(group.desktopId)
            launchPulse.restart()
            return
        }
        if (wins.length === 1) {
            const w = wins[0]
            if (w === Shell.activeWindow && !w.minimized)
                Shell.minimize(w)
            else
                Shell.activate(w)
            return
        }
        // Several windows: cycle through them, starting with the most recent.
        const ordered = Shell.focusOrder.filter(w => wins.indexOf(w) >= 0)
        if (hasActive) {
            const i = ordered.indexOf(Shell.activeWindow)
            Shell.activate(ordered[(i + 1) % ordered.length])
        } else {
            Shell.activate(ordered[0] || wins[0])
        }
    }

    function jumpList() {
        const g = mapToItem(Shell.root, width / 2, 0)
        const entries = []
        if (group.desktopId) {
            entries.push({ text: info.name || group.desktopId, icon: btn.iconSource, bold: true, action: () => Shell.launchApp(group.desktopId) })
            entries.push({ separator: true })
            if (Prefs.isPinned(group.desktopId))
                entries.push({ text: "Unpin this program from taskbar", icon: Theme.icon("pin"), action: () => Prefs.unpin(group.desktopId) })
            else
                entries.push({ text: "Pin this program to taskbar", icon: Theme.icon("pin"), action: () => Prefs.pin(group.desktopId) })
        }
        if (running) {
            entries.push({ text: wins.length > 1 ? "Close all windows" : "Close window", icon: Theme.icon("close"),
                           action: () => btn.wins.slice().forEach(w => w.close()) })
        }
        Shell.showMenu(entries, Math.max(0, g.x - 90), g.y - 4 - (entries.length * 22 + 10))
    }

    // Running indicator: a glassy button face
    Rectangle {
        id: face
        anchors.fill: parent
        anchors.margins: 2
        anchors.topMargin: 2
        radius: 3
        visible: !Theme.isModern && (btn.running || btn.hovered || ma.pressed)
        opacity: btn.running ? 1 : 0.8
        border.color: Qt.rgba(0, 0, 0, btn.hasActive ? 0.75 : 0.55)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, ma.pressed ? 0.12 : btn.hasActive ? 0.42 : btn.hovered ? 0.36 : 0.22) }
            GradientStop { position: 0.48; color: Qt.rgba(1, 1, 1, btn.hasActive ? 0.18 : btn.hovered ? 0.16 : 0.08) }
            GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, btn.hasActive ? 0.08 : 0.02) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, btn.hasActive ? 0.20 : btn.hovered ? 0.14 : 0.05) }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 2
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, btn.hasActive ? 0.55 : 0.30)
        }
        // stacked edge for groups with more than one window
        Rectangle {
            visible: btn.wins.length > 1
            anchors.right: parent.right
            anchors.rightMargin: -3
            y: 2
            width: 3
            height: parent.height - 4
            radius: 1
            color: Qt.rgba(1, 1, 1, 0.18)
            border.color: Qt.rgba(0, 0, 0, 0.5)
        }
    }
    // Modern: soft tile + indicator pill
    Rectangle {
        visible: Theme.isModern && (btn.hovered || btn.hasActive)
        anchors.fill: parent
        anchors.margins: 3
        radius: 5
        color: Qt.rgba(1, 1, 1, ma.pressed ? 0.05 : btn.hasActive ? 0.13 : 0.08)
        border.color: Qt.rgba(1, 1, 1, btn.hasActive ? 0.10 : 0.05)
    }
    Rectangle {
        visible: Theme.isModern && btn.running
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        width: btn.hasActive ? 16 : 6
        height: 3
        radius: 1.5
        color: btn.hasActive ? Qt.lighter(Theme.accent, 1.5) : "#9a9a9a"
        Behavior on width { NumberAnimation { duration: Theme.anim(150) } }
    }

    // Hot-track light under the cursor
    RadialGradient {
        anchors.fill: face
        visible: btn.hovered && !Theme.isModern
        horizontalOffset: ma.mouseX - width / 2
        verticalOffset: height * 0.35
        horizontalRadius: width * 0.9
        verticalRadius: height * 0.9
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.65, 0.88, 1, 0.45) }
            GradientStop { position: 0.6; color: Qt.rgba(0.65, 0.88, 1, 0.0) }
        }
    }
    Rectangle { // attention flash
        anchors.fill: face
        radius: 3
        color: "#ff9a2e"
        opacity: btn.flash ? 0.6 : 0
    }

    AppIcon {
        id: ico
        x: btn.showLabel ? 8 : (parent.width - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        size: Theme.taskbarIconSize
        name: btn.iconSource
        scale: ma.pressed ? 0.92 : 1
        SequentialAnimation on y {
            id: launchPulse
            running: false
            NumberAnimation { to: ico.y - 4; duration: Theme.anim(120) }
            NumberAnimation { to: ico.y; duration: Theme.anim(160); easing.type: Easing.OutBounce }
        }
    }
    Text {
        visible: btn.showLabel
        anchors.left: ico.right
        anchors.leftMargin: 6
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: btn.label
        color: "white"
        elide: Text.ElideRight
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        style: Text.Raised
        styleColor: "#90000000"
        renderType: Text.NativeRendering
    }

    Timer {
        id: hoverTimer
        interval: 420
        running: btn.hovered && btn.running && !ma.pressed
        onTriggered: {
            const g = btn.mapToItem(Shell.root, btn.width / 2, 0)
            Shell.showThumbnails(btn.group.key, g.x)
        }
    }
    onHoveredChanged: if (!hovered) Shell.hideThumbnailsSoon()

    // Drag a pinned button sideways to reorder the pins.
    property real dragOffset: 0
    property bool dragging: false
    transform: Translate { x: btn.dragOffset }
    z: dragging ? 10 : 0

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        property real pressX: 0
        onPressed: (m) => { pressX = m.x; btn.dragging = false }
        onPositionChanged: (m) => {
            if (!pressed || !(pressedButtons & Qt.LeftButton) || !btn.group.pinned)
                return
            const dx = m.x - pressX
            if (!btn.dragging && Math.abs(dx) < 8)
                return
            btn.dragging = true
            Shell.hideThumbnails()
            btn.dragOffset = dx
        }
        onReleased: {
            if (btn.dragging) {
                const pins = Prefs.pinnedApps
                const idx = pins.indexOf(btn.group.desktopId)
                const steps = Math.round(btn.dragOffset / btn.width)
                if (idx >= 0 && steps !== 0)
                    Prefs.movePinned(btn.group.desktopId, Math.max(0, Math.min(pins.length - 1, idx + steps)))
            }
            btn.dragOffset = 0
        }
        onClicked: (m) => {
            if (btn.dragging) {
                btn.dragging = false
                return
            }
            Shell.hideThumbnails()
            if (m.button === Qt.RightButton) {
                btn.jumpList()
            } else if (m.button === Qt.MiddleButton || (m.modifiers & Qt.ShiftModifier)) {
                if (btn.group.desktopId)
                    Shell.launchApp(btn.group.desktopId)
            } else {
                Shell.closePopups()
                btn.activateOrMinimize()
            }
        }
    }
}
