import QtQuick
import Vitrum
import Vitrum.Core

// Small message box. kind: "missing-windows" | "missing-java" | "info"
FocusScope {
    id: dlg
    property var frame: null
    property string kind: "info"
    property string file: ""
    property string message: ""
    readonly property bool missing: kind === "missing-windows" || kind === "missing-java"
    Component.onCompleted: if (frame) frame.internalTitle = missing ? Files.fileName(file) : "Vitrum"

    Rectangle { anchors.fill: parent; color: "white" }
    Image { x: 18; y: 20; width: 32; height: 32; sourceSize: Qt.size(64, 64); source: Theme.icon(dlg.kind === "missing-java" ? "jar" : dlg.missing ? "exe" : "about") }
    VText {
        x: 64; y: 18
        width: parent.width - 80
        wrapMode: Text.Wrap
        maximumLineCount: 5
        text: dlg.kind === "missing-windows"
              ? "To open “" + Files.fileName(dlg.file) + "”, Windows app support needs to be installed. It only takes a moment and lets you run most Windows programs."
              : dlg.kind === "missing-java"
                ? "To open “" + Files.fileName(dlg.file) + "”, a Java runtime needs to be installed."
                : dlg.message
    }
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width; height: 44
        color: Theme.face
        Rectangle { width: parent.width; height: 1; color: "#dfdfdf" }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Button7 {
                visible: dlg.missing
                text: "Install"
                isDefault: true
                enabled: Compat.installCommand(dlg.kind === "missing-java" ? "java" : "windows").length > 0
                onClicked: { Compat.installRuntime(dlg.kind === "missing-java" ? "java" : "windows"); dlg.frame.close() }
            }
            Button7 { text: dlg.missing ? "Cancel" : "OK"; isDefault: !dlg.missing; onClicked: dlg.frame.close() }
        }
    }
}
