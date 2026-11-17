import QtQuick
import Vitrum
import Vitrum.Core

// A ribbon group: controls on top, the group's name centred underneath and
// an etched divider on the right. When the window is too narrow the group
// collapses into one large button; its controls are then shown in a drop-
// down by moving `contentItem` into the panel (see expandRequested).
Item {
    id: group
    property string title: ""
    property string icon: ""
    property bool divider: true
    property bool collapsed: false
    default property alias content: holder.data
    readonly property alias holderItem: holder
    property Item contentItem: null     // the controls, also while shown in a drop-down
    property bool popped: false
    Component.onCompleted: if (holder.children.length) contentItem = holder.children[0]
    property real contentWidth: collapsed ? collapsedButton.width : holder.childrenRect.width
    signal expandRequested(Item group, Item button)
    implicitWidth: Math.max(contentWidth, caption.implicitWidth) + 12 + (divider ? 2 : 0)
    height: parent ? parent.height : 92

    Item {
        id: holder
        visible: !group.collapsed
        x: 6 + Math.max(0, (caption.implicitWidth - group.contentWidth) / 2)
        y: 3
        width: group.contentWidth
        height: group.height - 22
    }
    PaintRibbonButton {
        id: collapsedButton
        visible: group.collapsed
        x: holder.x
        y: 3
        large: true
        arrow: true
        width: Math.max(44, implicitWidth)
        iconName: group.icon
        text: group.title
        checked: group.popped
        onClicked: group.expandRequested(group, collapsedButton)
        onArrowClicked: group.expandRequested(group, collapsedButton)
    }
    VText {
        id: caption
        anchors.horizontalCenter: holder.horizontalCenter
        y: group.height - 18
        width: Math.min(implicitWidth, group.width - 4)
        horizontalAlignment: Text.AlignHCenter
        text: group.title
        color: "#3b5577"
        font.pixelSize: 11
    }
    Rectangle {
        visible: group.divider
        anchors.right: parent.right
        anchors.rightMargin: 1
        y: 3
        width: 1
        height: parent.height - 6
        gradient: Gradient {
            GradientStop { position: 0; color: "#00b7cbe4" }
            GradientStop { position: 0.25; color: "#b7cbe4" }
            GradientStop { position: 0.8; color: "#b7cbe4" }
            GradientStop { position: 1; color: "#00b7cbe4" }
        }
    }
    Rectangle {
        visible: group.divider
        anchors.right: parent.right
        y: 3
        width: 1
        height: parent.height - 6
        color: Qt.rgba(1, 1, 1, 0.7)
    }
}
