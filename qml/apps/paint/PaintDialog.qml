import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// A modal dialog window drawn inside an app: glass frame, title, close
// button, and a face-coloured client area. Blocks input to the app behind it.
FocusScope {
    id: dlg
    property string title: ""
    property Item tracking: null        // the owning WindowFrame, for the glass
    property real clientWidth: 320
    property real clientHeight: 200
    property bool open: false
    default property alias content: client.data
    signal rejected()

    anchors.fill: parent
    visible: open
    z: 1000
    // A small owner window (e.g. the Snipping Tool) grows while the dialog
    // is up and shrinks back afterwards.
    property size grownFrom: Qt.size(0, 0)
    function fitOwner() {
        const f = tracking
        if (!f || f.maximized || !f.isInternal)
            return
        const needW = box.width + 24, needH = box.height + 24
        if (width >= needW && height >= needH)
            return
        grownFrom = Qt.size(f.internalWidth, f.internalHeight)
        f.internalWidth = Math.max(f.internalWidth, needW)
        f.internalHeight = Math.max(f.internalHeight, needH)
        const a = Shell.workArea
        if (f.x + f.width > a.x + a.width)
            f.x = Math.max(a.x, a.x + a.width - f.width)
        if (f.y + f.height > a.y + a.height)
            f.y = Math.max(a.y, a.y + a.height - f.height)
    }
    onOpenChanged: {
        if (open) {
            fitOwner()
            box.x = Math.round((width - box.width) / 2)
            box.y = Math.max(0, Math.round((height - box.height) / 2) - 20)
            forceActiveFocus()
        } else {
            if (grownFrom.width > 0 && tracking) {
                tracking.internalWidth = grownFrom.width
                tracking.internalHeight = grownFrom.height
                grownFrom = Qt.size(0, 0)
            }
            // Give the keyboard back to the app behind.
            focus = false
            if (parent && tracking && Shell.activeWindow === tracking)
                parent.forceActiveFocus()
        }
    }
    Keys.onEscapePressed: dlg.rejected()

    MouseArea { // modal
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onWheel: (w) => { w.accepted = true }
    }

    Item {
        id: box
        readonly property real bw: Theme.frameBorder
        readonly property real th: Theme.titleHeight
        width: dlg.clientWidth + 2 * bw
        height: dlg.clientHeight + th + bw

        RectangularGlow {
            x: 2; y: 5
            width: parent.width - 4
            height: parent.height - 4
            glowRadius: 14
            spread: 0.05
            cornerRadius: glowRadius + Theme.frameRadius
            color: "#70000000"
        }
        GlassPanel {
            anchors.fill: parent
            tracking: dlg.tracking
            active: true
            role: "window"
            radius: Theme.frameRadius
            outerOpacity: 0.7
        }
        GlowText {
            x: box.bw + 4
            y: Math.round((box.th - 18) / 2) + 1
            width: box.width - 70
            height: 18
            text: dlg.title
            color: Theme.titleText
            font.pixelSize: Theme.fontSize
            glow: Theme.titleGlow
        }
        MouseArea {
            x: 0; y: 0
            width: parent.width - 50
            height: box.th
            property point start
            onPressed: (m) => { start = Qt.point(m.x, m.y) }
            onPositionChanged: (m) => {
                if (!pressed)
                    return
                box.x = Math.max(-box.width + 60, Math.min(dlg.width - 60, box.x + m.x - start.x))
                box.y = Math.max(0, Math.min(dlg.height - 30, box.y + m.y - start.y))
            }
        }
        CaptionButton {
            anchors.right: parent.right
            anchors.rightMargin: Theme.isModern ? box.bw : box.bw - 1
            y: Theme.isModern ? box.bw : 0
            width: Theme.isModern ? 46 : 43
            height: Theme.isModern ? box.th - box.bw : Theme.captionHeight
            kind: "close"
            lastInRow: true
            active: true
            onClicked: dlg.rejected()
        }
        Rectangle {
            visible: !Theme.isModern
            x: box.bw - 1; y: box.th - 1
            width: dlg.clientWidth + 2
            height: dlg.clientHeight + 2
            color: "transparent"
            border.color: Qt.rgba(0, 0, 0, 0.55)
        }
        Rectangle {
            id: client
            x: box.bw; y: box.th
            width: dlg.clientWidth
            height: dlg.clientHeight
            color: Theme.face
        }
    }
}
