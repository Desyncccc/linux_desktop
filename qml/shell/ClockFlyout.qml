import QtQuick
import Vitrum
import Vitrum.Core

Flyout {
    id: fly
    open: Shell.flyout === "clock"
    anchorX: Shell.flyoutX
    width: 300
    height: 330
    property date now: new Date()
    property int viewYear: now.getFullYear()
    property int viewMonth: now.getMonth()

    onOpenChanged: if (open) { now = new Date(); viewYear = now.getFullYear(); viewMonth = now.getMonth() }
    Timer { interval: 1000; running: fly.open; repeat: true; onTriggered: fly.now = new Date() }

    VText {
        x: 16; y: 12
        text: Qt.formatTime(fly.now, Prefs.clock24h ? "HH:mm:ss" : "h:mm:ss AP")
        font.pixelSize: 30
        font.weight: Font.Light
        color: "#1e3287"
    }
    VText {
        x: 18; y: 54
        text: Qt.formatDate(fly.now, "dddd, MMMM d, yyyy")
        color: "#1e3287"
    }
    Separator { x: 12; y: 78; width: parent.width - 24 }

    Item {
        x: 12; y: 84
        width: parent.width - 24
        height: 26
        VText {
            anchors.centerIn: parent
            text: Qt.locale().standaloneMonthName(fly.viewMonth) + " " + fly.viewYear
            font.bold: true
        }
        HoverItem {
            width: 24; height: 24
            VText { anchors.centerIn: parent; text: "◀"; color: "#4a6fa5" }
            onClicked: { if (fly.viewMonth === 0) { fly.viewMonth = 11; fly.viewYear-- } else fly.viewMonth-- }
        }
        HoverItem {
            anchors.right: parent.right
            width: 24; height: 24
            VText { anchors.centerIn: parent; text: "▶"; color: "#4a6fa5" }
            onClicked: { if (fly.viewMonth === 11) { fly.viewMonth = 0; fly.viewYear++ } else fly.viewMonth++ }
        }
    }

    Grid {
        id: cal
        x: 14; y: 114
        columns: 7
        readonly property int firstDay: Qt.locale().firstDayOfWeek % 7
        readonly property int offset: (new Date(fly.viewYear, fly.viewMonth, 1).getDay() - firstDay + 7) % 7
        Repeater {
            model: 7
            VText {
                required property int index
                width: 39; height: 22
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: Qt.locale().dayName((cal.firstDay + index) % 7, Locale.ShortFormat).substring(0, 2)
                color: Theme.textMuted
            }
        }
        Repeater {
            model: 42
            Item {
                id: day
                required property int index
                readonly property date d: new Date(fly.viewYear, fly.viewMonth, index - cal.offset + 1)
                readonly property bool inMonth: d.getMonth() === fly.viewMonth
                readonly property bool today: d.toDateString() === fly.now.toDateString()
                width: 39; height: 28
                Rectangle {
                    anchors.fill: parent; anchors.margins: 1
                    visible: day.today
                    color: "#dcebfc"
                    border.color: "#3d7bad"
                    radius: 2
                }
                VText {
                    anchors.centerIn: parent
                    text: day.d.getDate()
                    color: day.inMonth ? Theme.text : Theme.textDisabled
                }
            }
        }
    }
    VText {
        x: 0; width: parent.width
        y: parent.height - 26
        horizontalAlignment: Text.AlignHCenter
        text: "Change date and time settings..."
        color: Theme.link
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Shell.openSettings("time") }
    }
}
