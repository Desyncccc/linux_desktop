import QtQuick
import Vitrum
import Vitrum.Core

// Scenic-ribbon button: large (32px icon over a label) or small (16px icon
// with an optional label). `arrow` adds a drop-down chevron; with `split`
// the chevron is a separate hot zone that emits arrowClicked().
Item {
    id: rb
    property string iconName: ""
    property string text: ""
    property bool large: false
    property bool arrow: false
    property bool split: false
    property bool checked: false
    property string tip: ""
    readonly property bool hovered: ma.containsMouse
    readonly property bool pressed: ma.pressed
    readonly property bool arrowHovered: split && ma.containsMouse && (large ? ma.mouseY > iconBox.y + iconBox.height + 2 : ma.mouseX > width - 13)
    signal clicked()
    signal arrowClicked()

    implicitWidth: large ? Math.max(42, labelCol.implicitWidth + 10) : (smallRow.implicitWidth + 8)
    implicitHeight: large ? 66 : 22
    opacity: enabled ? 1 : 0.45

    function face(top) {
        if (pressed || checked)
            return top ? "#d6e7fb" : "#b5d0f1"
        return top ? "#fbfdff" : "#dfecfb"
    }

    Rectangle {
        anchors.fill: parent
        radius: 3
        visible: rb.enabled && (rb.hovered || rb.pressed || rb.checked)
        border.color: rb.pressed || rb.checked ? "#7da2ce" : "#a7c5e9"
        gradient: Gradient {
            GradientStop { position: 0; color: rb.face(true) }
            GradientStop { position: 1; color: rb.face(false) }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: 2
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, 0.75)
        }
        Rectangle { // split divider
            visible: rb.split
            color: "#a7c5e9"
            x: rb.large ? 2 : parent.width - 13
            y: rb.large ? iconBox.y + iconBox.height + 3 : 2
            width: rb.large ? parent.width - 4 : 1
            height: rb.large ? 1 : parent.height - 4
        }
    }

    // ---- large layout
    Item {
        id: iconBox
        visible: rb.large
        width: 32; height: 32
        x: (parent.width - width) / 2
        y: 3
        AppIcon {
            visible: rb.iconName.length > 0
            anchors.centerIn: parent
            size: 32
            name: rb.iconName.length ? Theme.icon(rb.iconName) : ""
        }
    }
    Column {
        id: labelCol
        visible: rb.large
        anchors.horizontalCenter: parent.horizontalCenter
        y: iconBox.y + iconBox.height + 3
        spacing: -1
        Repeater {
            model: rb.large ? rb.text.split("\n") : []
            VText {
                required property string modelData
                anchors.horizontalCenter: parent.horizontalCenter
                text: modelData
                color: "#1e395b"
                font.pixelSize: 11
            }
        }
        VText {
            visible: rb.arrow
            anchors.horizontalCenter: parent.horizontalCenter
            text: "▾"
            color: "#1e395b"
            font.pixelSize: 10
        }
    }

    // ---- small layout
    Row {
        id: smallRow
        visible: !rb.large
        x: 4
        height: parent.height
        spacing: 4
        AppIcon {
            visible: rb.iconName.length > 0
            anchors.verticalCenter: parent.verticalCenter
            size: 16
            name: rb.iconName.length ? Theme.icon(rb.iconName) : ""
        }
        VText {
            visible: rb.text.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: rb.text
            color: "#1e395b"
        }
        VText {
            visible: rb.arrow
            anchors.verticalCenter: parent.verticalCenter
            text: "▾"
            color: "#1e395b"
            font.pixelSize: 10
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: (m) => {
            Shell.hideTooltip()
            if (rb.split && (rb.large ? m.y > iconBox.y + iconBox.height + 2 : m.x > rb.width - 13))
                rb.arrowClicked()
            else if (rb.arrow && !rb.split)
                rb.arrowClicked()
            else
                rb.clicked()
        }
        onContainsMouseChanged: {
            if (containsMouse && rb.tip.length > 0) {
                const p = rb.mapToItem(Shell.root, 0, rb.height - 14)
                tipTimer.pos = p
                tipTimer.restart()
            } else {
                tipTimer.stop()
                Shell.hideTooltip()
            }
        }
    }
    Timer {
        id: tipTimer
        property point pos
        interval: 700
        onTriggered: if (ma.containsMouse) Shell.showTooltip(rb.tip, pos.x, pos.y)
    }
    // Menus anchor below the button.
    function menuPos() { return mapToItem(Shell.root, 0, height) }
}
