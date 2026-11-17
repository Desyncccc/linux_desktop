import QtQuick
import Vitrum

// Slim scroll position indicator for Flickables.
Rectangle {
    property Flickable flickable: null
    parent: flickable
    visible: flickable && flickable.contentHeight > flickable.height
    x: flickable ? flickable.width - width - 1 : 0
    width: 5
    radius: 2
    color: Theme.c("#90a0a0a0")
    y: flickable ? (flickable.contentY / Math.max(1, flickable.contentHeight)) * flickable.height : 0
    height: flickable ? Math.max(20, flickable.height * flickable.height / Math.max(1, flickable.contentHeight)) : 0
}
