import QtQuick
import Vitrum
import Vitrum.Core

// Desktop background: one of the procedural built-ins or a picture.
Item {
    id: wp
    readonly property string setting: Prefs.wallpaper
    readonly property bool builtin: setting.indexOf("builtin:") === 0
    readonly property string variant: builtin ? setting.substring(8) : ""

    readonly property var palettes: ({
        "aurora":   { base: "#1d5fa8", glow: "#5fd3ff", v: 0 },
        "ember":    { base: "#7a3410", glow: "#ffb35c", v: 1 },
        "verdant":  { base: "#1c6236", glow: "#a6f28a", v: 2 },
        "dusk":     { base: "#45277a", glow: "#ff8fd6", v: 3 },
        "graphite": { base: "#2b3743", glow: "#a8c3da", v: 4 }
    })
    readonly property var palette: palettes[variant] || palettes["aurora"]

    Rectangle { anchors.fill: parent; color: "#14365e" }

    ShaderEffect {
        anchors.fill: parent
        visible: wp.builtin || picture.status !== Image.Ready
        property size resolution: Qt.size(width, height)
        property color baseColor: wp.palette.base
        property color glowColor: wp.palette.glow
        property real variant: wp.palette.v
        fragmentShader: "qrc:/qt/qml/Vitrum/shaders/wallpaper.frag.qsb"
    }
    Image {
        id: picture
        anchors.fill: parent
        visible: !wp.builtin && status === Image.Ready
        source: wp.builtin ? "" : (wp.setting.indexOf("/") === 0 ? "file://" + wp.setting : wp.setting)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize: Qt.size(width, height)
        cache: false
    }
}
