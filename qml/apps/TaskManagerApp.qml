import QtQuick
import Vitrum
import Vitrum.Core

// Task Manager: running windows with Switch To / End Task.
FocusScope {
    id: tm
    property var frame: null
    property var selectedWin: null

    Rectangle { anchors.fill: parent; color: Theme.face }
    Row {
        x: 8; y: 8
        spacing: -1
        Rectangle {
            width: 90; height: 24
            color: Theme.c("white")
            border.color: Theme.c("#898c95")
            VText { anchors.centerIn: parent; text: "Applications" }
            Rectangle { anchors.bottom: parent.bottom; x: 1; width: parent.width - 2; height: 1; color: Theme.c("white") }
        }
    }
    Rectangle {
        id: panel
        x: 8; y: 31
        width: parent.width - 16
        height: parent.height - y - 52
        color: Theme.c("white")
        border.color: Theme.c("#898c95")
        Rectangle {
            id: hdr
            x: 1; y: 1
            width: parent.width - 2; height: 24
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.c("#ffffff") }
                GradientStop { position: 1; color: Theme.c("#f1f2f4") }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.c("#d5d5d5") }
            VText { x: 8; anchors.verticalCenter: parent.verticalCenter; text: "Task" }
            VText { x: parent.width - 100; anchors.verticalCenter: parent.verticalCenter; text: "Status" }
        }
        ListView {
            id: list
            x: 1; y: hdr.height + 1
            width: parent.width - 2
            height: parent.height - y - 1
            clip: true
            model: Shell.windows.filter(w => !w.closing)
            delegate: HoverItem {
                id: taskItem
                required property var modelData
                width: list.width; height: 24
                radius: 0
                selected: tm.selectedWin === modelData
                AppIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; size: 16; name: taskItem.modelData.iconSource }
                VText { x: 28; width: parent.width - 140; anchors.verticalCenter: parent.verticalCenter; text: taskItem.modelData.title }
                VText { x: parent.width - 100; anchors.verticalCenter: parent.verticalCenter; text: taskItem.modelData.minimized ? "Minimized" : "Running" }
                onClicked: tm.selectedWin = modelData
                onDoubleClicked: Shell.activate(modelData)
            }
        }
    }
    VText { x: 10; anchors.bottom: parent.bottom; anchors.bottomMargin: 18; text: "Windows: " + list.count; color: Theme.textMuted }
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        spacing: 8
        Button7 { text: "End Task"; enabled: tm.selectedWin !== null; onClicked: { tm.selectedWin.close(); tm.selectedWin = null } }
        Button7 { text: "Switch To"; enabled: tm.selectedWin !== null; onClicked: Shell.activate(tm.selectedWin) }
        Button7 { text: "New Task..."; onClicked: Shell.openRun() }
    }
}
