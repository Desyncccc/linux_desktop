import QtQuick
import Vitrum
import Vitrum.Core

// Glass with the frame treatment for the current theme: dark outer edge,
// light inner edge and a sheen (aero), hairline edges (modern), or an
// opaque bevelled face (basic).
Item {
    id: panel
    property alias tracking: glass.tracking
    property alias tint: glass.tint
    property alias intensity: glass.intensity
    property alias brightness: glass.brightness
    property alias streaks: glass.streaks
    property alias role: glass.role
    property real radius: Theme.frameRadius
    property bool active: true
    property bool sheen: true
    property real outerOpacity: 0.65

    GlassSurface {
        id: glass
        anchors.fill: parent
        radius: panel.radius
        activeLook: panel.active
        role: "panel"
        intensity: Theme.glassIntensity(panel.active)
        brightness: panel.active ? 0.03 : 0.12
    }
    Rectangle {
        visible: panel.sheen && Theme.isAero
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, panel.radius - 1)
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, panel.active ? 0.30 : 0.22) }
            GradientStop { position: 0.45; color: Qt.rgba(1, 1, 1, 0.06) }
            GradientStop { position: 0.46; color: Qt.rgba(1, 1, 1, 0.0) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.05) }
        }
    }
    Rectangle { // inner highlight
        visible: !Theme.isModern
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, panel.radius - 1)
        color: "transparent"
        border.color: Qt.rgba(1, 1, 1, Theme.isBasic ? 0.7 : 0.45)
    }
    Rectangle { // outer edge
        anchors.fill: parent
        radius: panel.radius
        color: "transparent"
        border.color: Theme.isModern ? Qt.rgba(0, 0, 0, panel.outerOpacity > 0 ? 0.28 : 0)
                    : Theme.isBasic ? Qt.rgba(0.2, 0.3, 0.45, panel.outerOpacity > 0 ? 0.85 : 0)
                    : Qt.rgba(0, 0, 0, panel.outerOpacity)
    }
}
