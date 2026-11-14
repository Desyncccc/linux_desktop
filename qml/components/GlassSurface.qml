import QtQuick
import Vitrum
import Vitrum.Core

// A rectangle of "glass": the blurred wallpaper behind it, tinted.
// Set `tracking` to the item that moves (e.g. a window) so the sampled
// region follows it. The look follows the active theme:
//   aero   - tinted, streaked glass
//   modern - flat frosted acrylic
//   basic  - opaque, no transparency
ShaderEffect {
    id: glass
    property Item tracking: null
    property string role: "window"      // "window" | "panel" (taskbar, menus, flyouts)
    property bool activeLook: true
    property color tint: Theme.accent
    property real intensity: Theme.glassIntensity(true)
    property real saturation: Theme.glassSaturation
    property real streaks: 0.6
    property real brightness: 0.03
    property real alpha: Theme.isBasic ? 0 : 1.0
    property real radius: 0

    readonly property color uTint: Theme.isModern ? Theme.modernTint(role, activeLook) : tint
    readonly property real uIntensity: Theme.isModern ? Theme.modernIntensity(role) : intensity
    readonly property real uSaturation: Theme.isModern ? 1.0 : saturation
    readonly property real uStreaks: Theme.isModern ? 0.0 : streaks
    readonly property real uBrightness: Theme.isModern ? 0.0 : brightness

    property variant source: Shell.blurTexture
    property rect region: Qt.rect(0, 0, 1, 1)
    property size itemSize: Qt.size(width, height)

    fragmentShader: "qrc:/qt/qml/Vitrum/shaders/glass.frag.qsb"
    blending: true

    // Opaque "Basic" fill
    Rectangle {
        anchors.fill: parent
        visible: Theme.isBasic
        radius: glass.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.basicTop(glass.role, glass.activeLook) }
            GradientStop { position: 1.0; color: Theme.basicBottom(glass.role, glass.activeLook) }
        }
    }

    function updateRegion() {
        if (!Shell.root || width <= 0 || height <= 0)
            return
        const p = glass.mapToItem(Shell.root, 0, 0)
        const sw = Math.max(1, Shell.screenWidth), sh = Math.max(1, Shell.screenHeight)
        region = Qt.rect(p.x / sw, p.y / sh, width / sw, height / sh)
    }

    onWidthChanged: updateRegion()
    onHeightChanged: updateRegion()
    onXChanged: updateRegion()
    onYChanged: updateRegion()
    Component.onCompleted: updateRegion()

    Connections {
        target: glass.tracking
        ignoreUnknownSignals: true
        function onXChanged() { glass.updateRegion() }
        function onYChanged() { glass.updateRegion() }
        function onWidthChanged() { glass.updateRegion() }
        function onHeightChanged() { glass.updateRegion() }
    }
    Connections {
        target: Shell
        function onScreenWidthChanged() { glass.updateRegion() }
        function onScreenHeightChanged() { glass.updateRegion() }
    }
}
