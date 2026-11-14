import QtQuick
import Vitrum
import Vitrum.Core

FocusScope {
    property var frame: null
    Rectangle { anchors.fill: parent; color: "white" }
    AboutContent { x: 24; y: 20 }
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width; height: 44
        color: Theme.face
        Rectangle { width: parent.width; height: 1; color: "#dfdfdf" }
        Button7 { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: "OK"; isDefault: true; onClicked: frame.close() }
    }
}
