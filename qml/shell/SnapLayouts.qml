import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// Layout picker shown when hovering a window's maximize button.
Item {
    id: sl
    readonly property Item win: Shell.snapLayoutsFor
    visible: win !== null
    width: 248
    height: 118
    x: Math.max(4, Math.min(Shell.snapLayoutsAnchor.x - width / 2, Shell.screenWidth - width - 4))
    y: Math.min(Shell.snapLayoutsAnchor.y + 4, Shell.screenHeight - height - 4)

    property bool inside: hover.containsMouse
    Timer {
        interval: 700
        running: sl.visible && !sl.inside
        onTriggered: Shell.snapLayoutsFor = null
    }
    MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.AllButtons; onPressed: (m) => m.accepted = true }

    RectangularGlow { anchors.fill: panel; glowRadius: 8; spread: 0.1; cornerRadius: 14; color: "#70000000" }
    GlassPanel { id: panel; anchors.fill: parent; tracking: sl; radius: 6 }

    readonly property var layouts: [
        [{ t: "left", x: 0, w: 0.5 }, { t: "right", x: 0.5, w: 0.5 }],
        [{ t: "l23", x: 0, w: 0.66 }, { t: "r13", x: 0.66, w: 0.34 }],
        [{ t: "t1", x: 0, w: 0.33 }, { t: "t2", x: 0.33, w: 0.34 }, { t: "t3", x: 0.67, w: 0.33 }],
        [{ t: "tl", x: 0, w: 0.5, y: 0, h: 0.5 }, { t: "tr", x: 0.5, w: 0.5, y: 0, h: 0.5 },
         { t: "bl", x: 0, w: 0.5, y: 0.5, h: 0.5 }, { t: "br", x: 0.5, w: 0.5, y: 0.5, h: 0.5 }]
    ]
    Grid {
        anchors.centerIn: parent
        columns: 2
        spacing: 10
        Repeater {
            model: sl.layouts
            delegate: Rectangle {
                id: layout
                required property var modelData
                width: 104; height: 44
                radius: 4
                color: Qt.rgba(0, 0, 0, 0.25)
                border.color: Qt.rgba(1, 1, 1, 0.45)
                Repeater {
                    model: layout.modelData
                    delegate: Rectangle {
                        id: zone
                        required property var modelData
                        x: 3 + modelData.x * (layout.width - 6) + 1
                        y: 3 + (modelData.y || 0) * (layout.height - 6) + 1
                        width: modelData.w * (layout.width - 6) - 2
                        height: (modelData.h || 1) * (layout.height - 6) - 2
                        radius: 2
                        color: zoneMouse.containsMouse ? Qt.lighter(Theme.accent, 1.4) : Qt.rgba(1, 1, 1, 0.35)
                        border.color: Qt.rgba(1, 1, 1, 0.7)
                        MouseArea {
                            id: zoneMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                const w = sl.win
                                Shell.snapLayoutsFor = null
                                if (w) { w.snap(zone.modelData.t); Shell.activate(w) }
                            }
                        }
                    }
                }
            }
        }
    }
}
