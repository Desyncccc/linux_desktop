import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

Item {
    id: tl
    visible: Shell.tooltipText.length > 0
    width: label.implicitWidth + 14
    height: label.implicitHeight + 8
    x: Math.max(2, Math.min(Shell.tooltipPos.x - 4, Shell.screenWidth - width - 2))
    y: Shell.tooltipPos.y > Shell.screenHeight - Theme.taskbarHeight - 4
       ? Shell.screenHeight - Theme.taskbarHeight - height - 6
       : Math.min(Shell.tooltipPos.y + 22, Shell.screenHeight - height - 2)
    RectangularGlow { anchors.fill: box; glowRadius: 3; spread: 0.1; cornerRadius: 5; color: Theme.c("#40000000") }
    Rectangle {
        id: box
        anchors.fill: parent
        radius: 2
        border.color: Theme.c("#767676")
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.c("#ffffff") }
            GradientStop { position: 1; color: Theme.c("#e4e5f0") }
        }
    }
    VText {
        id: label
        x: 7; y: 4
        text: Shell.tooltipText
        color: Theme.c("#4c4c4c")
        elide: Text.ElideNone
    }
}
