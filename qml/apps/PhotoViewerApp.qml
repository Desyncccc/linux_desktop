import QtQuick
import Vitrum
import Vitrum.Core

// Photo Viewer with zoom, rotate and next/previous.
FocusScope {
    id: pv
    property var frame: null
    property string path: ""
    property var siblings: []
    property real zoom: 1
    property int rotation: 0
    onPathChanged: { siblings = path ? Files.siblingImages(path) : []; zoom = 1; rotation = 0; if (frame) frame.internalTitle = Files.fileName(path) + " - Photo Viewer" }
    Component.onCompleted: forceActiveFocus()

    function step(d) {
        const i = siblings.indexOf(path)
        if (i >= 0 && siblings.length > 1)
            path = siblings[(i + d + siblings.length) % siblings.length]
    }
    Keys.onLeftPressed: step(-1)
    Keys.onRightPressed: step(1)
    Keys.onPressed: (e) => {
        if (e.key === Qt.Key_Plus || e.key === Qt.Key_Equal) { zoom = Math.min(8, zoom * 1.25); e.accepted = true }
        else if (e.key === Qt.Key_Minus) { zoom = Math.max(0.1, zoom / 1.25); e.accepted = true }
        else if (e.key === Qt.Key_Delete) { Files.moveToTrash([path]); step(1); e.accepted = true }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#f4f8fc" }
            GradientStop { position: 1; color: "#dfe8f2" }
        }
    }
    Flickable {
        id: flick
        width: parent.width
        height: parent.height - bar.height
        clip: true
        contentWidth: Math.max(width, img.paintedWidth * pv.zoom)
        contentHeight: Math.max(height, img.paintedHeight * pv.zoom)
        Image {
            id: img
            anchors.centerIn: parent
            width: flick.width - 20
            height: flick.height - 20
            source: pv.path ? "file://" + pv.path : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            autoTransform: true
            scale: pv.zoom
            rotation: pv.rotation
            smooth: true
            mipmap: true
        }
        MouseArea {
            anchors.fill: parent
            onWheel: (w) => { pv.zoom = Math.max(0.1, Math.min(8, pv.zoom * (w.angleDelta.y > 0 ? 1.15 : 1 / 1.15))) }
            onDoubleClicked: pv.zoom = 1
        }
    }
    Rectangle {
        id: bar
        anchors.bottom: parent.bottom
        width: parent.width; height: 46
        gradient: Gradient {
            GradientStop { position: 0; color: "#dbe6f3" }
            GradientStop { position: 1; color: "#c1d3e8" }
        }
        Rectangle { width: parent.width; height: 1; color: "#9fb4cc" }
        component Tool: Item {
            id: tool
            property string label: ""
            property bool big: false
            signal activated()
            width: big ? 40 : 30; height: big ? 40 : 30
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                border.color: "#2b5c97"
                gradient: Gradient {
                    GradientStop { position: 0; color: toolMouse.containsMouse ? "#bfe4ff" : "#9ccaf0" }
                    GradientStop { position: 0.5; color: toolMouse.containsMouse ? "#4ea3ef" : "#3d7fc8" }
                    GradientStop { position: 1; color: toolMouse.containsMouse ? "#7cc6ff" : "#2f68ad" }
                }
                Text { anchors.centerIn: parent; text: tool.label; color: "white"; font.pixelSize: tool.big ? 18 : 14; font.bold: true }
            }
            MouseArea { id: toolMouse; anchors.fill: parent; hoverEnabled: true; onClicked: tool.activated() }
        }
        Row {
            anchors.centerIn: parent
            spacing: 10
            Tool { label: "−"; onActivated: pv.zoom = Math.max(0.1, pv.zoom / 1.25) }
            Tool { label: "1:1"; onActivated: pv.zoom = 1 }
            Tool { label: "◀"; big: true; onActivated: pv.step(-1) }
            Tool { label: "▶"; big: true; onActivated: pv.step(1) }
            Tool { label: "↺"; onActivated: pv.rotation -= 90 }
            Tool { label: "↻"; onActivated: pv.rotation += 90 }
            Tool { label: "+"; onActivated: pv.zoom = Math.min(8, pv.zoom * 1.25) }
        }
    }
}
