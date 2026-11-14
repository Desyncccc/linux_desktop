import QtQuick

Item {
    property bool vertical: false
    property color dark: "#d5dfe5"
    property color light: "#ffffff"
    implicitWidth: vertical ? 2 : 100
    implicitHeight: vertical ? 100 : 2
    Rectangle { width: parent.vertical ? 1 : parent.width; height: parent.vertical ? parent.height : 1; color: parent.dark }
    Rectangle { x: parent.vertical ? 1 : 0; y: parent.vertical ? 0 : 1; width: parent.vertical ? 1 : parent.width; height: parent.vertical ? parent.height : 1; color: parent.light }
}
