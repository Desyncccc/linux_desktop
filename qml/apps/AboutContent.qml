import QtQuick
import Vitrum
import Vitrum.Core

Column {
    spacing: 10
    Row {
        spacing: 16
        Image { source: Theme.icon("vitrum"); width: 72; height: 72; sourceSize: Qt.size(144, 144) }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            VText { text: "Vitrum"; font.pixelSize: 30; color: Theme.c("#1e3287") }
            VText { text: "Version " + Session.version; color: Theme.textMuted }
        }
    }
    Separator { width: 400 }
    Grid {
        columns: 2
        columnSpacing: 20
        rowSpacing: 6
        component Key: VText { color: Theme.textMuted; width: 110 }
        Key { text: "Computer name:" }
        VText { text: Sys.hostName }
        Key { text: "User:" }
        VText { text: Sys.realName + " (" + Sys.userName + ")" }
        Key { text: "System:" }
        VText { text: Sys.osName }
        Key { text: "Kernel:" }
        VText { text: Sys.kernel }
        Key { text: "Processor:" }
        VText { text: Sys.cpuModel; width: 300 }
        Key { text: "Memory:" }
        VText { text: Sys.memoryTotal }
        Key { text: "Display:" }
        VText { text: Shell.screenWidth + " × " + Shell.screenHeight + " (" + Session.platform + ")" }
        Key { text: "Toolkit:" }
        VText { text: "Qt " + Session.qtVersion }
    }
}
