import QtQuick
import Vitrum
import Vitrum.Core

// "Edit Colors": basic and custom swatches, a hue/saturation spectrum with a
// luminosity bar, and HSL/RGB fields.
PaintDialog {
    id: cd
    property real hue: 0
    property real sat: 0
    property real lum: 0
    readonly property color current: Qt.hsla(hue, sat, lum, 1)
    property var custom: ["#ffffff", "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#ffffff",
                          "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#ffffff"]
    property int customSlot: 0
    signal accepted(color c)

    title: "Edit Colors"
    clientWidth: 470
    clientHeight: 318

    readonly property var basic: [
        "#ff8080", "#ffff80", "#80ff80", "#00ff80", "#80ffff", "#0080ff", "#ff80c0", "#ff80ff",
        "#ff0000", "#ffff00", "#80ff00", "#00ff40", "#00ffff", "#0080c0", "#8080c0", "#ff00ff",
        "#804040", "#ff8040", "#00ff00", "#008080", "#004080", "#8080ff", "#800040", "#ff0080",
        "#800000", "#ff8000", "#008000", "#008040", "#0000ff", "#0000a0", "#800080", "#8000ff",
        "#400000", "#804000", "#004000", "#004040", "#000080", "#000040", "#400040", "#400080",
        "#000000", "#808000", "#808040", "#808080", "#408080", "#c0c0c0", "#400040", "#ffffff"
    ]

    function show(c) {
        setColor(c)
        open = true
    }
    function setColor(c) {
        const k = Qt.color(c)
        hue = k.hslHue < 0 ? 0 : k.hslHue
        sat = k.hslSaturation
        lum = k.hslLightness
    }
    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
    onRejected: open = false

    component Swatch: Rectangle {
        property color swatch: "white"
        signal picked()
        width: 20; height: 16
        color: swatch
        border.color: sMa.containsMouse ? "#3c7fb1" : "#7a7a7a"
        border.width: Qt.colorEqual(swatch, cd.current) ? 2 : 1
        MouseArea { id: sMa; anchors.fill: parent; hoverEnabled: true; onClicked: parent.picked() }
    }
    component Field: Row {
        property string label: ""
        property int value: 0
        property int maximum: 255
        signal edited(int v)
        spacing: 4
        VText { width: 40; text: parent.label; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
        TextField7 {
            id: f
            width: 40
            text: String(parent.value)
            input.validator: IntValidator { bottom: 0; top: 255 }
            onAccepted: parent.edited(Math.min(parent.maximum, parseInt(text) || 0))
        }
        Connections {
            target: f.input
            function onActiveFocusChanged() {
                if (!f.input.activeFocus)
                    f.parent.edited(Math.min(f.parent.maximum, parseInt(f.text) || 0))
            }
        }
    }

    VText { x: 10; y: 8; text: "Basic colors:" }
    Grid {
        x: 10; y: 26
        columns: 8
        spacing: 4
        Repeater {
            model: cd.basic
            Swatch { required property string modelData; swatch: modelData; onPicked: cd.setColor(modelData) }
        }
    }
    VText { x: 10; y: 152; text: "Custom colors:" }
    Grid {
        x: 10; y: 170
        columns: 8
        spacing: 4
        Repeater {
            model: cd.custom
            Swatch {
                required property string modelData
                required property int index
                swatch: modelData
                onPicked: { cd.customSlot = index; cd.setColor(modelData) }
            }
        }
    }
    Button7 { x: 10; y: 222; width: 188; text: "Define Custom Colors >>"; enabled: false }

    // ---- spectrum
    Rectangle {
        id: spectrum
        x: 218; y: 10
        width: 180; height: 152
        border.color: "#7a7a7a"
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#ff0000" }
            GradientStop { position: 0.167; color: "#ffff00" }
            GradientStop { position: 0.333; color: "#00ff00" }
            GradientStop { position: 0.5; color: "#00ffff" }
            GradientStop { position: 0.667; color: "#0000ff" }
            GradientStop { position: 0.833; color: "#ff00ff" }
            GradientStop { position: 1.0; color: "#ff0000" }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            gradient: Gradient {
                GradientStop { position: 0; color: "#00808080" }
                GradientStop { position: 1; color: "#ff808080" }
            }
        }
        Item { // crosshair
            x: 1 + cd.hue * (spectrum.width - 2) - 9
            y: 1 + (1 - cd.sat) * (spectrum.height - 2) - 9
            width: 19; height: 19
            Rectangle { x: 0; y: 8; width: 6; height: 3; color: "black" }
            Rectangle { x: 13; y: 8; width: 6; height: 3; color: "black" }
            Rectangle { x: 8; y: 0; width: 3; height: 6; color: "black" }
            Rectangle { x: 8; y: 13; width: 3; height: 6; color: "black" }
        }
        MouseArea {
            anchors.fill: parent
            preventStealing: true
            function pick(m) {
                cd.hue = cd.clamp((m.x - 1) / (spectrum.width - 2), 0, 0.999)
                cd.sat = cd.clamp(1 - (m.y - 1) / (spectrum.height - 2), 0, 1)
                if (cd.lum <= 0.01 || cd.lum >= 0.99)
                    cd.lum = 0.5
            }
            onPressed: (m) => pick(m)
            onPositionChanged: (m) => { if (pressed) pick(m) }
        }
    }
    // ---- luminosity bar
    Rectangle {
        id: lumBar
        x: 410; y: 10
        width: 14; height: 152
        border.color: "#7a7a7a"
        gradient: Gradient {
            GradientStop { position: 0; color: "white" }
            GradientStop { position: 0.5; color: Qt.hsla(cd.hue, cd.sat, 0.5, 1) }
            GradientStop { position: 1; color: "black" }
        }
        MouseArea {
            x: 0; y: 0
            width: parent.width + 20; height: parent.height
            preventStealing: true
            function pick(m) { cd.lum = cd.clamp(1 - m.y / lumBar.height, 0, 1) }
            onPressed: (m) => pick(m)
            onPositionChanged: (m) => { if (pressed) pick(m) }
        }
    }
    VText { // pointer
        x: lumBar.x + lumBar.width + 2
        y: lumBar.y + (1 - cd.lum) * lumBar.height - height / 2
        text: "◀"
        font.pixelSize: 11
    }
    // ---- preview + fields
    Rectangle {
        x: 218; y: 172
        width: 60; height: 42
        color: cd.current
        border.color: "#7a7a7a"
    }
    VText { x: 218; y: 216; width: 60; horizontalAlignment: Text.AlignHCenter; text: "Color|Solid"; font.pixelSize: 11 }
    Column {
        x: 286; y: 170
        spacing: 3
        Field { label: "Hue:"; value: Math.round(cd.hue * 239); maximum: 239; onEdited: (v) => cd.hue = v / 239 }
        Field { label: "Sat:"; value: Math.round(cd.sat * 240); maximum: 240; onEdited: (v) => cd.sat = v / 240 }
        Field { label: "Lum:"; value: Math.round(cd.lum * 240); maximum: 240; onEdited: (v) => cd.lum = v / 240 }
    }
    Column {
        x: 380; y: 170
        spacing: 3
        Field { label: "Red:"; value: Math.round(cd.current.r * 255); onEdited: (v) => cd.setColor(Qt.rgba(v / 255, cd.current.g, cd.current.b, 1)) }
        Field { label: "Green:"; value: Math.round(cd.current.g * 255); onEdited: (v) => cd.setColor(Qt.rgba(cd.current.r, v / 255, cd.current.b, 1)) }
        Field { label: "Blue:"; value: Math.round(cd.current.b * 255); onEdited: (v) => cd.setColor(Qt.rgba(cd.current.r, cd.current.g, v / 255, 1)) }
    }
    Button7 {
        x: 218; y: 254
        width: 240
        text: "Add to Custom Colors"
        onClicked: {
            const c = cd.custom.slice()
            c[cd.customSlot] = cd.current.toString()
            cd.custom = c
            cd.customSlot = (cd.customSlot + 1) % 16
        }
    }
    Row {
        x: 10; y: 286
        spacing: 8
        Button7 { width: 90; text: "OK"; isDefault: true; onClicked: { cd.open = false; cd.accepted(cd.current) } }
        Button7 { width: 90; text: "Cancel"; onClicked: cd.open = false }
    }
}
