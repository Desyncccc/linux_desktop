import QtQuick
import Vitrum
import Vitrum.Core

// Slider with the classic thin track and glossy thumb.
Item {
    id: s
    property real from: 0
    property real to: 100
    property real value: 0
    property real stepSize: 1
    property bool vertical: false
    property bool light: false   // white track for dark/glass backgrounds
    signal moved(real value)

    implicitWidth: vertical ? 22 : 160
    implicitHeight: vertical ? 160 : 22

    readonly property real ratio: (value - from) / Math.max(0.0001, to - from)
    readonly property real span: (vertical ? height : width) - 12

    Rectangle {
        x: s.vertical ? (s.width - width) / 2 : 6
        y: s.vertical ? 6 : (s.height - height) / 2
        width: s.vertical ? 4 : s.width - 12
        height: s.vertical ? s.height - 12 : 4
        radius: 2
        color: s.light ? Qt.rgba(1, 1, 1, 0.35) : "#e7eaea"
        border.color: s.light ? Qt.rgba(0, 0, 0, 0.35) : "#b0b0b0"
        Rectangle {
            visible: !s.vertical
            width: parent.width * s.ratio
            height: parent.height
            radius: 2
            color: s.light ? "#9fd0ff" : "#4a9de0"
        }
        Rectangle {
            visible: s.vertical
            anchors.bottom: parent.bottom
            width: parent.width
            height: parent.height * s.ratio
            radius: 2
            color: s.light ? "#9fd0ff" : "#4a9de0"
        }
    }
    Rectangle {
        id: thumb
        width: s.vertical ? 20 : 11
        height: s.vertical ? 11 : 20
        radius: 2
        x: s.vertical ? (s.width - width) / 2 : 6 + s.ratio * s.span - width / 2
        y: s.vertical ? 6 + (1 - s.ratio) * s.span - height / 2 : (s.height - height) / 2
        border.color: ma.pressed ? "#2c628b" : ma.containsMouse ? "#3c7fb1" : "#707070"
        gradient: Gradient {
            GradientStop { position: 0; color: ma.containsMouse ? "#eaf6fd" : "#f2f2f2" }
            GradientStop { position: 1; color: ma.containsMouse ? "#a7d9f5" : "#cfcfcf" }
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        function setFrom(mx, my) {
            let r = s.vertical ? 1 - (my - 6) / s.span : (mx - 6) / s.span
            r = Math.max(0, Math.min(1, r))
            let v = s.from + r * (s.to - s.from)
            if (s.stepSize > 0)
                v = Math.round(v / s.stepSize) * s.stepSize
            if (v !== s.value) {
                s.value = v
                s.moved(v)
            }
        }
        onPressed: (m) => setFrom(m.x, m.y)
        onPositionChanged: (m) => { if (pressed) setFrom(m.x, m.y) }
        onWheel: (w) => {
            const step = (s.to - s.from) / 20
            let v = Math.max(s.from, Math.min(s.to, s.value + (w.angleDelta.y > 0 ? step : -step)))
            s.value = v
            s.moved(v)
        }
    }
}
