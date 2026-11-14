import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// Notifications and quick actions, sliding in from the right edge.
Item {
    id: ac
    width: 370
    height: Shell.screenHeight - Theme.taskbarHeight
    property bool open: Shell.actionCenterOpen
    x: Shell.screenWidth - (open ? width : 0)
    visible: x < Shell.screenWidth
    Behavior on x { NumberAnimation { duration: Theme.anim(200); easing.type: Easing.OutCubic } }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onPressed: (m) => m.accepted = true }

    GlassPanel {
        anchors.fill: parent
        anchors.rightMargin: -8
        tracking: ac
        radius: 0
        intensity: Theme.transparency ? Math.min(0.92, Theme.intensity + 0.3) : 0.96
        tint: Qt.darker(Theme.accent, 2.2)
        sheen: false
    }

    Text {
        x: 16; y: 14
        text: "Notifications"
        color: "white"
        font.family: Theme.font
        font.pixelSize: 18
        renderType: Text.NativeRendering
    }
    Text {
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: 20
        text: "Clear all"
        visible: Notifications.count > 0
        color: "#bfe0ff"
        font.family: Theme.font
        font.pixelSize: Theme.fontSize
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Notifications.clearAll() }
    }

    ListView {
        id: list
        x: 10; y: 48
        width: parent.width - 20
        height: tiles.y - y - 12
        clip: true
        spacing: 6
        model: Notifications
        boundsBehavior: Flickable.StopAtBounds
        delegate: NotificationCard {
            required property var model
            width: list.width
            notificationId: model.notificationId
            appName: model.appName
            appIcon: model.appIcon
            summary: model.summary
            body: model.body
            actions: model.actions
            image: model.image
            time: model.time
            onDismissed: Notifications.dismiss(notificationId)
            onActionClicked: (key) => Notifications.invokeAction(notificationId, key)
        }
        Text {
            anchors.centerIn: parent
            visible: Notifications.count === 0
            text: "No new notifications"
            color: Qt.rgba(1, 1, 1, 0.75)
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
        }
    }

    // Quick actions
    Column {
        id: tiles
        x: 10
        width: parent.width - 20
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        spacing: 10

        Grid {
            columns: 4
            spacing: 6
            component Tile: Item {
                id: tile
                property string label: ""
                property string iconName: ""
                property bool on: false
                property bool toggle: true
                signal activated()
                width: (tiles.width - 18) / 4
                height: 58
                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    border.color: Qt.rgba(0, 0, 0, 0.6)
                    gradient: Gradient {
                        GradientStop { position: 0; color: tile.on ? Qt.lighter(Theme.accent, 1.35) : Qt.rgba(1, 1, 1, tileMouse.containsMouse ? 0.30 : 0.20) }
                        GradientStop { position: 1; color: tile.on ? Theme.accent : Qt.rgba(1, 1, 1, tileMouse.containsMouse ? 0.14 : 0.07) }
                    }
                    Rectangle { anchors.fill: parent; anchors.margins: 1; radius: 3; color: "transparent"; border.color: Qt.rgba(1, 1, 1, 0.35) }
                }
                Image {
                    x: 8; y: 8
                    width: 18; height: 18
                    sourceSize: Qt.size(36, 36)
                    source: tile.iconName
                }
                Text {
                    x: 8; y: 34
                    width: parent.width - 12
                    text: tile.label
                    color: "white"
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSizeSmall
                    renderType: Text.NativeRendering
                }
                MouseArea { id: tileMouse; anchors.fill: parent; hoverEnabled: true; onClicked: tile.activated() }
            }
            Tile {
                label: Sys.hasWifi ? (Sys.wifiEnabled ? (Sys.networkName || "Wi-Fi") : "Wi-Fi") : (Sys.networkType === "none" ? "Offline" : "Network")
                iconName: Theme.icon(Sys.hasWifi ? (Sys.wifiEnabled ? "net-wifi" : "net-wifi-off") : "net-wired")
                on: Sys.hasWifi ? Sys.wifiEnabled : Sys.networkType !== "none"
                onActivated: if (Sys.hasWifi) Sys.setWifiEnabled(!Sys.wifiEnabled)
            }
            Tile {
                label: "Focus assist"
                iconName: Theme.icon("moon")
                on: Prefs.doNotDisturb
                onActivated: Prefs.doNotDisturb = !Prefs.doNotDisturb
            }
            Tile {
                label: "Night light"
                iconName: Theme.icon("nightlight")
                on: Prefs.nightLight
                onActivated: Prefs.nightLight = !Prefs.nightLight
            }
            Tile {
                label: "Transparency"
                iconName: Theme.icon("transparency")
                on: Prefs.transparency
                onActivated: Prefs.transparency = !Prefs.transparency
            }
            Tile {
                label: "Screenshot"
                iconName: Theme.icon("screenshot")
                onActivated: { Shell.closePopups(); Shell.screenshotRequested() }
            }
            Tile {
                label: "All settings"
                iconName: Theme.icon("settings-mono")
                onActivated: Shell.openSettings("")
            }
            Tile {
                label: "Lock"
                iconName: Theme.icon("lock")
                onActivated: Shell.lock()
            }
            Tile {
                label: "Desktop"
                iconName: Theme.icon("desktop")
                onActivated: { Shell.closePopups(); Shell.toggleDesktop() }
            }
        }

        component SliderRow: Row {
            property string iconName: ""
            property alias value: sl.value
            signal moved(real v)
            spacing: 10
            Image { width: 18; height: 18; sourceSize: Qt.size(36, 36); source: parent.iconName; anchors.verticalCenter: parent.verticalCenter }
            Slider7 { id: sl; width: tiles.width - 40; light: true; from: 0; to: 100; onMoved: (v) => parent.moved(v) }
        }
        SliderRow {
            visible: Sys.hasBacklight
            iconName: Theme.icon("sun")
            value: Sys.brightness
            onMoved: (v) => Sys.setBrightness(v)
        }
        SliderRow {
            iconName: Theme.icon(Sys.muted ? "volume-muted" : "volume")
            value: Sys.volume
            enabled: Sys.hasAudio
            opacity: enabled ? 1 : 0.5
            onMoved: (v) => Sys.setVolume(v)
        }
    }
}
