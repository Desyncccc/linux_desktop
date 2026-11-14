import QtQuick
import Vitrum
import Vitrum.Core

// Classic tooltip shown after hovering `target` (a MouseArea) for a moment.
Item {
    id: tip
    property Item target: null
    property string text: ""
    property bool shown: false

    Timer {
        interval: 700
        running: tip.target !== null && tip.target.containsMouse && !tip.target.pressed && tip.text.length > 0
        onTriggered: {
            if (!Shell.root || !tip.target)
                return
            const p = tip.target.mapToItem(Shell.root, tip.target.mouseX, tip.target.mouseY)
            Shell.showTooltip(tip.text, p.x, p.y)
            tip.shown = true
        }
    }
    Connections {
        target: tip.target
        ignoreUnknownSignals: true
        function onContainsMouseChanged() {
            if (!tip.target.containsMouse && tip.shown) {
                Shell.hideTooltip()
                tip.shown = false
            }
        }
        function onPressedChanged() {
            if (tip.shown) {
                Shell.hideTooltip()
                tip.shown = false
            }
        }
    }
}
