import QtQuick
import Vitrum
import Vitrum.Core

// Icon from the freedesktop theme (by name), a file, or a bundled SVG.
Image {
    id: img
    property string name: ""
    property string fallback: "application-x-executable"
    property int size: 32
    width: size
    height: size
    sourceSize: Qt.size(size, size)
    fillMode: Image.PreserveAspectFit
    smooth: true
    asynchronous: false
    source: {
        if (name.indexOf("qrc:") === 0 || name.indexOf("file:") === 0 || name.indexOf("image:") === 0)
            return name
        return Theme.themeIcon(name, fallback)
    }
}
