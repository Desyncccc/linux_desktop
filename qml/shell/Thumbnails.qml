import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// Live window previews above a taskbar button. Hovering a preview peeks
// at that window; clicking it switches to it.
Item {
    id: th
    property var taskbar: null
    readonly property var group: Shell.thumbKey !== "" && taskbar ? taskbar.groupByKey(Shell.thumbKey) : null
    readonly property var wins: group ? group.windows : []
    readonly property bool shown: wins.length > 0 && !Shell.startOpen && !Shell.menuOpen && !Shell.switcherOpen
    readonly property int tw: 196
    readonly property int tht: 128

    visible: shown
    width: row.width + 16
    height: tht + 16
    x: Math.max(4, Math.min(Shell.thumbX - width / 2, Shell.screenWidth - width - 4))
    y: Shell.screenHeight - Theme.taskbarHeight - height - 2

    Timer {
        interval: 350
        running: Shell.thumbHideRequested && !area.containsMouse
        onTriggered: Shell.hideThumbnails()
    }
    MouseArea {
        id: area
        anchors.fill: parent
        anchors.bottomMargin: -4
        hoverEnabled: true
        onExited: Shell.hideThumbnailsSoon()
        onPressed: (m) => m.accepted = true
    }

    RectangularGlow { anchors.fill: panel; glowRadius: 8; spread: 0.1; cornerRadius: 14; color: "#70000000" }
    GlassPanel { id: panel; anchors.fill: parent; tracking: th; radius: 6 }

    Row {
        id: row
        x: 8; y: 8
        spacing: 6
        Repeater {
            model: th.shown ? th.wins : []
            delegate: Item {
                id: t
                required property var modelData
                width: th.tw; height: th.tht
                readonly property bool hot: tMouse.containsMouse || closeMouse.containsMouse
                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    visible: t.hot || t.modelData === Shell.activeWindow
                    color: Qt.rgba(1, 1, 1, t.hot ? 0.22 : 0.12)
                    border.color: Qt.rgba(1, 1, 1, t.hot ? 0.75 : 0.4)
                }
                AppIcon {
                    x: 6; y: 6
                    size: 16
                    name: t.modelData.iconSource
                }
                Text {
                    x: 26; y: 6
                    width: parent.width - 52
                    text: t.modelData.title
                    color: "white"
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.fontSize
                    style: Text.Raised
                    styleColor: "#a0000000"
                    renderType: Text.NativeRendering
                }
                ShaderEffectSource {
                    readonly property real s: Math.min((th.tw - 16) / Math.max(1, t.modelData.width), (th.tht - 34) / Math.max(1, t.modelData.height))
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 27 + ((th.tht - 34) - height) / 2
                    width: t.modelData.width * s
                    height: t.modelData.height * s
                    sourceItem: th.shown ? t.modelData.thumbnailSource : null
                    live: true
                }
                MouseArea {
                    id: tMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onContainsMouseChanged: peek.restart()
                    onClicked: (m) => {
                        Shell.hideThumbnails()
                        if (m.button === Qt.MiddleButton) t.modelData.close()
                        else Shell.activate(t.modelData)
                    }
                }
                Timer {
                    id: peek
                    interval: 500
                    onTriggered: Shell.peekWindow = tMouse.containsMouse ? t.modelData : (Shell.peekWindow === t.modelData ? null : Shell.peekWindow)
                }
                Rectangle {
                    visible: t.hot
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    y: 4
                    width: 22; height: 18
                    radius: 3
                    border.color: Qt.rgba(0, 0, 0, 0.5)
                    color: closeMouse.containsMouse ? "#d9442b" : Qt.rgba(1, 1, 1, 0.2)
                    Image { anchors.centerIn: parent; width: 10; height: 10; sourceSize: Qt.size(20, 20); source: Theme.icon("close") }
                    MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; onClicked: t.modelData.close() }
                }
            }
        }
    }
}
