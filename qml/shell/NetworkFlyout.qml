import QtQuick
import Vitrum
import Vitrum.Core

Flyout {
    id: fly
    open: Shell.flyout === "network"
    anchorX: Shell.flyoutX
    width: 280
    height: col.implicitHeight + 24

    Column {
        id: col
        x: 14; y: 12
        width: parent.width - 28
        spacing: 8
        VText { text: "Currently connected to:"; color: Theme.textMuted }
        Row {
            spacing: 10
            Rectangle {
                width: 32; height: 32; radius: 4
                gradient: Gradient {
                    GradientStop { position: 0; color: "#6fb5f2" }
                    GradientStop { position: 1; color: "#2a6fc0" }
                }
                Image {
                    anchors.centerIn: parent
                    width: 20; height: 20
                    sourceSize: Qt.size(40, 40)
                    source: Sys.networkType === "wifi" ? Theme.icon("net-wifi") : Sys.networkType === "wired" ? Theme.icon("net-wired") : Theme.icon("net-none")
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                VText {
                    text: Sys.networkType === "none" ? "Not connected" : (Sys.networkName || (Sys.networkType === "wifi" ? "Wireless network" : "Wired network"))
                    font.bold: true
                }
                VText {
                    text: Sys.networkType === "none" ? "No connections are available" : "Internet access"
                    color: Theme.textMuted
                }
            }
        }
        Separator { width: parent.width }
        CheckBox7 {
            visible: Sys.hasWifi
            text: "Wi-Fi"
            checked: Sys.wifiEnabled
            onToggled: (c) => Sys.setWifiEnabled(c)
        }
        VText {
            text: "Open Network and Sharing settings"
            color: Theme.link
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Shell.closePopups()
                    if (Launcher.commandExists("nm-connection-editor"))
                        Launcher.run(["nm-connection-editor"])
                    else if (Launcher.commandExists("nmtui"))
                        Launcher.run([Launcher.terminal, "-e", "nmtui"])
                    else
                        Shell.notify("Network settings", "No network configuration tool is installed.", "network-wired")
                }
            }
        }
    }
}
