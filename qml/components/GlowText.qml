import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// Dark text on glass with the soft white "glow" plate behind it.
Item {
    id: root
    property alias text: label.text
    property alias font: label.font
    property alias color: label.color
    property alias elide: label.elide
    property alias horizontalAlignment: label.horizontalAlignment
    property bool glow: true
    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    RectangularGlow {
        visible: root.glow && label.text.length > 0
        x: -6
        y: label.height / 2 - 4
        width: Math.min(label.contentWidth, label.width) + 12
        height: 8
        glowRadius: 9
        spread: 0.35
        cornerRadius: 12
        color: Qt.rgba(1, 1, 1, 0.75)
    }
    VText {
        id: label
        width: root.width
        height: root.height
        verticalAlignment: Text.AlignVCenter
    }
}
