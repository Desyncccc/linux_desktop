import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// Lock screen: large clock over the wallpaper; any key or click reveals the
// sign-in panel. Passwords are verified with PAM.
FocusScope {
    id: lock
    anchors.fill: parent
    visible: Shell.locked
    property bool prompting: false
    property string error: ""
    property date now: new Date()

    onVisibleChanged: {
        prompting = false
        error = ""
        password.text = ""
        if (visible)
            lock.forceActiveFocus()
    }
    Timer { interval: 1000; running: lock.visible; repeat: true; onTriggered: lock.now = new Date() }

    function reveal() {
        if (!prompting) {
            prompting = true
            password.input.forceActiveFocus()
        }
    }
    function submit() {
        if (Auth.busy)
            return
        error = ""
        Auth.authenticate(password.text)
    }
    Connections {
        target: Auth
        function onSucceeded() {
            if (!Shell.locked)
                return
            password.text = ""
            Shell.locked = false
            Shell.restoreFocus()
        }
        function onFailed(message) {
            lock.error = message
            password.text = ""
            password.input.forceActiveFocus()
            shake.restart()
        }
    }

    Keys.onPressed: (e) => { reveal(); e.accepted = true }

    // Blurred wallpaper with a dim
    ShaderEffectSource {
        anchors.fill: parent
        sourceItem: Shell.blurTexture
        visible: Shell.blurTexture !== null
    }
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: lock.prompting ? 0.35 : 0.15
        Behavior on opacity { NumberAnimation { duration: Theme.anim(250) } }
    }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: lock.reveal()
        onWheel: (w) => w.accepted = true
    }

    // Big clock
    Column {
        x: 60
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 70
        opacity: lock.prompting ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim(220) } }
        Text {
            text: Qt.formatTime(lock.now, Prefs.clock24h ? "HH:mm" : "h:mm")
            color: "white"
            font.family: Theme.font
            font.pixelSize: 110
            font.weight: Font.Light
            layer.enabled: true
            layer.effect: DropShadow { radius: 12; samples: 25; color: "#80000000"; verticalOffset: 2 }
        }
        Text {
            text: Qt.formatDate(lock.now, "dddd, MMMM d")
            color: "white"
            font.family: Theme.font
            font.pixelSize: 38
            font.weight: Font.Light
            layer.enabled: true
            layer.effect: DropShadow { radius: 10; samples: 21; color: "#80000000"; verticalOffset: 2 }
        }
    }

    // Sign-in panel
    Column {
        id: panel
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -30
        spacing: 14
        opacity: lock.prompting ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.anim(220) } }
        transform: Translate { id: shakeT; x: 0 }
        SequentialAnimation {
            id: shake
            NumberAnimation { target: shakeT; property: "x"; to: -12; duration: 50 }
            NumberAnimation { target: shakeT; property: "x"; to: 12; duration: 70 }
            NumberAnimation { target: shakeT; property: "x"; to: -8; duration: 60 }
            NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 50 }
        }

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 140; height: 140
            RectangularGlow { anchors.fill: frameRect; glowRadius: 10; spread: 0.2; cornerRadius: 18; color: "#60000000" }
            GlassPanel { id: frameRect; anchors.fill: parent; radius: 8; tracking: panel }
            Rectangle {
                anchors.fill: parent; anchors.margins: 10
                radius: 4
                clip: true
                gradient: Gradient {
                    GradientStop { position: 0; color: "#8fc8f0" }
                    GradientStop { position: 1; color: "#2d6db5" }
                }
                Image {
                    anchors.fill: parent
                    visible: Sys.avatar.length > 0
                    source: Sys.avatar
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(240, 240)
                }
                Image {
                    visible: Sys.avatar.length === 0
                    anchors.centerIn: parent
                    width: 72; height: 72
                    source: Theme.icon("switch-user")
                    sourceSize: Qt.size(144, 144)
                }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Sys.realName
            color: "white"
            font.family: Theme.font
            font.pixelSize: 26
            layer.enabled: true
            layer.effect: DropShadow { radius: 8; samples: 17; color: "#a0000000"; verticalOffset: 1 }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4
            TextField7 {
                id: password
                width: 220; height: 27
                rounded: true
                placeholder: "Password"
                echoMode: TextInput.Password
                enabled: !Auth.busy
                onAccepted: lock.submit()
                Keys.onEscapePressed: { password.text = ""; lock.prompting = false; lock.forceActiveFocus() }
            }
            Rectangle {
                width: 27; height: 27
                radius: 14
                border.color: Qt.rgba(0, 0, 0, 0.6)
                gradient: Gradient {
                    GradientStop { position: 0; color: goMouse.containsMouse ? "#9ed6ff" : "#6fb5f2" }
                    GradientStop { position: 1; color: goMouse.containsMouse ? "#3b8de0" : "#2a6fc0" }
                }
                Image { anchors.centerIn: parent; width: 14; height: 14; sourceSize: Qt.size(28, 28); source: Theme.icon("arrow-right") }
                MouseArea { id: goMouse; anchors.fill: parent; hoverEnabled: true; onClicked: lock.submit() }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Auth.busy ? "Welcome" : lock.error
            visible: text.length > 0
            color: "white"
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 1
        }
    }

    // Power
    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 30
        width: 36; height: 30
        radius: 4
        border.color: Qt.rgba(0, 0, 0, 0.6)
        gradient: Gradient {
            GradientStop { position: 0; color: pwrMouse.containsMouse ? "#f7b8a8" : Qt.rgba(1, 1, 1, 0.3) }
            GradientStop { position: 1; color: pwrMouse.containsMouse ? "#c43b22" : Qt.rgba(1, 1, 1, 0.08) }
        }
        Image { anchors.centerIn: parent; width: 16; height: 16; sourceSize: Qt.size(32, 32); source: Theme.icon("power") }
        MouseArea {
            id: pwrMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                const g = mapToItem(Shell.root, 0, 0)
                Shell.showMenu([
                    { text: "Sleep", icon: Theme.icon("sleep"), action: () => Sys.suspend() },
                    { text: "Restart", icon: Theme.icon("restart"), action: () => Sys.reboot() },
                    { text: "Shut down", icon: Theme.icon("power"), action: () => Sys.powerOff() }
                ], g.x - 120, g.y - 80)
            }
        }
    }
}
