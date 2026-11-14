import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// Alt+Tab switcher with live thumbnails.
Item {
    id: sw
    anchors.fill: parent
    visible: Shell.switcherOpen
    readonly property var list: Shell.switcherOpen ? Shell.focusOrder.filter(w => !w.closing) : []
    readonly property int cell: 140
    readonly property int perRow: Math.max(1, Math.min(list.length, Math.floor((width - 80) / (cell + 8))))

    onVisibleChanged: if (!visible) Shell.peekWindow = null
    Connections {
        target: Shell
        function onSwitcherIndexChanged() {
            if (Shell.switcherOpen && sw.list.length > 0)
                peekTimer.restart()
        }
    }
    Timer {
        id: peekTimer
        interval: 900
        onTriggered: if (Shell.switcherOpen) Shell.peekWindow = sw.list[Shell.switcherIndex] || null
    }

    RectangularGlow {
        anchors.fill: panel
        glowRadius: 14; spread: 0.1; cornerRadius: 20
        color: "#80000000"
    }
    GlassPanel {
        id: panel
        anchors.centerIn: parent
        tracking: sw
        width: grid.width + 32
        height: grid.height + titleLabel.height + 34
        radius: 7
        intensity: Theme.transparency ? Math.min(0.9, Theme.intensity + 0.2) : 0.95
    }
    Text {
        id: titleLabel
        anchors.horizontalCenter: panel.horizontalCenter
        y: panel.y + 10
        width: panel.width - 30
        horizontalAlignment: Text.AlignHCenter
        text: sw.list[Shell.switcherIndex] ? sw.list[Shell.switcherIndex].title : ""
        color: "white"
        elide: Text.ElideRight
        font.family: Theme.font
        font.pixelSize: Theme.fontSize + 1
        style: Text.Raised
        styleColor: "#a0000000"
        renderType: Text.NativeRendering
    }
    Grid {
        id: grid
        anchors.horizontalCenter: panel.horizontalCenter
        y: titleLabel.y + titleLabel.height + 10
        columns: sw.perRow
        spacing: 8
        Repeater {
            model: sw.list
            delegate: Item {
                id: tile
                required property var modelData
                required property int index
                readonly property bool sel: index === Shell.switcherIndex
                width: sw.cell; height: 104
                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    visible: tile.sel || tileMouse.containsMouse
                    color: Qt.rgba(1, 1, 1, tile.sel ? 0.25 : 0.12)
                    border.color: Qt.rgba(1, 1, 1, tile.sel ? 0.8 : 0.4)
                }
                ShaderEffectSource {
                    id: thumb
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -4
                    readonly property real s: Math.min((sw.cell - 16) / Math.max(1, tile.modelData.width), 80 / Math.max(1, tile.modelData.height))
                    width: tile.modelData.width * s
                    height: tile.modelData.height * s
                    sourceItem: Shell.switcherOpen ? tile.modelData.thumbnailSource : null
                    live: true
                    hideSource: false
                }
                AppIcon {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 6
                    size: 32
                    name: tile.modelData.iconSource
                }
                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { Shell.switcherIndex = tile.index; Shell.switchCommit() }
                }
            }
        }
    }
}
