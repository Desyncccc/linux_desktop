import QtQuick
import Vitrum
import Vitrum.Core

// Settings: sidebar of categories on the left, pages on the right.
FocusScope {
    id: app
    property var frame: null
    property string page: ""
    readonly property string current: page.length > 0 ? page : "personalize"

    readonly property var pages: [
        { id: "personalize", title: "Personalization", icon: Theme.icon("settings") },
        { id: "taskbar", title: "Taskbar and Start", icon: Theme.icon("apps") },
        { id: "display", title: "Display", icon: Theme.icon("computer") },
        { id: "notifications", title: "Notifications", icon: Theme.icon("about") },
        { id: "compat", title: "Windows app support", icon: Theme.icon("exe") },
        { id: "time", title: "Date and time", icon: Theme.icon("settings") },
        { id: "about", title: "About", icon: Theme.icon("about") }
    ]
    onCurrentChanged: if (frame) frame.internalTitle = "Settings - " + (pages.find(p => p.id === current) || pages[0]).title

    // Sidebar (light blue gradient like a classic control panel task pane)
    Rectangle {
        id: side
        width: 210
        height: parent.height
        gradient: Gradient {
            GradientStop { position: 0; color: "#eef5fc" }
            GradientStop { position: 1; color: "#d6e6f7" }
        }
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#b6c9df" }
        Column {
            x: 10; y: 14
            width: parent.width - 20
            spacing: 2
            VText { text: "Settings"; font.pixelSize: Theme.fontSizeLarge; color: "#1e3287"; bottomPadding: 10; leftPadding: 4 }
            Repeater {
                model: app.pages
                delegate: HoverItem {
                    id: pageItem
                    required property var modelData
                    width: parent.width
                    height: 30
                    selected: app.current === modelData.id
                    AppIcon { x: 6; anchors.verticalCenter: parent.verticalCenter; size: 18; name: pageItem.modelData.icon }
                    VText { x: 32; anchors.verticalCenter: parent.verticalCenter; text: pageItem.modelData.title; color: "#1e3287" }
                    onClicked: app.page = modelData.id
                }
            }
        }
    }

    Flickable {
        x: side.width
        width: parent.width - side.width
        height: parent.height
        clip: true
        contentHeight: content.height + 40
        boundsBehavior: Flickable.StopAtBounds
        Rectangle { width: parent.width; height: Math.max(parent.height, content.height + 40); color: "white" }
        Loader {
            id: content
            x: 26; y: 20
            width: parent.width - 52
            sourceComponent: ({ personalize: personalizePage, taskbar: taskbarPage, display: displayPage,
                                notifications: notificationsPage, compat: compatPage, time: timePage, about: aboutPage })[app.current] || personalizePage
        }
    }

    component Heading: VText { font.pixelSize: Theme.fontSizeTitle; color: "#1e3287"; bottomPadding: 6 }
    component SubHeading: VText { font.pixelSize: Theme.fontSizeLarge; color: "#1e3287"; topPadding: 14; bottomPadding: 2 }
    component Note: VText { color: Theme.textMuted; wrapMode: Text.Wrap; width: parent ? parent.width : 400 }

    Component {
        id: personalizePage
        Column {
            spacing: 8
            Heading { text: "Change the visuals and colors on your computer" }
            SubHeading { text: "Theme" }
            Row {
                spacing: 14
                Repeater {
                    model: [
                        { id: "aero", name: "Aero", note: "Glass with color and transparency" },
                        { id: "modern", name: "Modern", note: "Flat, frosted and rounded" },
                        { id: "basic", name: "Basic", note: "Simple and opaque" }
                    ]
                    delegate: Column {
                        id: themeCard
                        required property var modelData
                        spacing: 4
                        readonly property bool chosen: Theme.style === modelData.id
                        Rectangle {
                            width: 150; height: 94
                            radius: 3
                            border.width: themeCard.chosen ? 3 : 1
                            border.color: themeCard.chosen ? "#3399ff" : "#a0a0a0"
                            clip: true
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#173f6e" }
                                GradientStop { position: 1; color: "#3f8fd6" }
                            }
                            // miniature window
                            Rectangle {
                                x: 18; y: 12; width: 112; height: 62
                                radius: themeCard.modelData.id === "modern" ? 5 : 3
                                border.color: themeCard.modelData.id === "modern" ? "#40000000" : "#90000000"
                                gradient: Gradient {
                                    GradientStop { position: 0; color: themeCard.modelData.id === "aero" ? Qt.rgba(0.62, 0.78, 0.95, 0.85) : themeCard.modelData.id === "basic" ? "#d3e1f3" : "#f3f3f3" }
                                    GradientStop { position: 1; color: themeCard.modelData.id === "aero" ? Qt.rgba(0.35, 0.55, 0.85, 0.85) : themeCard.modelData.id === "basic" ? "#b4c9e6" : "#f3f3f3" }
                                }
                                Rectangle {
                                    x: themeCard.modelData.id === "modern" ? 1 : 5; y: themeCard.modelData.id === "modern" ? 16 : 18
                                    width: parent.width - 2 * x; height: parent.height - y - x
                                    color: "white"
                                    border.color: themeCard.modelData.id === "modern" ? "transparent" : "#80000000"
                                }
                                Rectangle {
                                    anchors.right: parent.right; anchors.rightMargin: themeCard.modelData.id === "modern" ? 1 : 5
                                    y: themeCard.modelData.id === "modern" ? 1 : 0
                                    width: themeCard.modelData.id === "modern" ? 16 : 18; height: themeCard.modelData.id === "modern" ? 14 : 10
                                    radius: themeCard.modelData.id === "modern" ? 0 : 2
                                    color: themeCard.modelData.id === "modern" ? "#c42b1c" : "#c9503c"
                                }
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 12
                                color: themeCard.modelData.id === "modern" ? "#1f1f1f" : themeCard.modelData.id === "basic" ? Qt.darker(Theme.accent, 1.4) : Qt.rgba(0.1, 0.2, 0.35, 0.8)
                            }
                            MouseArea { anchors.fill: parent; onClicked: Prefs.theme = themeCard.modelData.id }
                        }
                        VText { text: themeCard.modelData.name; font.bold: themeCard.chosen }
                        VText { text: themeCard.modelData.note; color: Theme.textMuted; font.pixelSize: Theme.fontSizeSmall }
                    }
                }
            }
            SubHeading { text: "Desktop background" }
            Flow {
                width: parent.width
                spacing: 10
                Repeater {
                    model: [
                        { id: "builtin:aurora", name: "Aurora", base: "#1d5fa8", glow: "#5fd3ff", v: 0 },
                        { id: "builtin:ember", name: "Ember", base: "#7a3410", glow: "#ffb35c", v: 1 },
                        { id: "builtin:verdant", name: "Verdant", base: "#1c6236", glow: "#a6f28a", v: 2 },
                        { id: "builtin:dusk", name: "Dusk", base: "#45277a", glow: "#ff8fd6", v: 3 },
                        { id: "builtin:graphite", name: "Graphite", base: "#2b3743", glow: "#a8c3da", v: 4 }
                    ]
                    delegate: Column {
                        required property var modelData
                        spacing: 3
                        Rectangle {
                            width: 112; height: 70
                            border.width: Prefs.wallpaper === modelData.id ? 3 : 1
                            border.color: Prefs.wallpaper === modelData.id ? "#3399ff" : "#a0a0a0"
                            ShaderEffect {
                                anchors.fill: parent
                                anchors.margins: parent.border.width
                                property size resolution: Qt.size(1366, 768)
                                property color baseColor: modelData.base
                                property color glowColor: modelData.glow
                                property real variant: modelData.v
                                fragmentShader: "qrc:/qt/qml/Vitrum/shaders/wallpaper.frag.qsb"
                            }
                            MouseArea { anchors.fill: parent; onClicked: Prefs.wallpaper = modelData.id }
                        }
                        VText { text: modelData.name; anchors.horizontalCenter: parent.horizontalCenter }
                    }
                }
            }
            Row {
                spacing: 6
                VText { text: "Picture location:"; anchors.verticalCenter: parent.verticalCenter }
                TextField7 {
                    id: wpPath
                    width: 300
                    text: Prefs.wallpaper.indexOf("builtin:") === 0 ? "" : Prefs.wallpaper
                    placeholder: "/path/to/picture.jpg"
                    onAccepted: if (text.length) Prefs.wallpaper = text
                }
                Button7 { text: "Apply"; onClicked: if (wpPath.text.length) Prefs.wallpaper = wpPath.text }
            }

            SubHeading { text: "Window color and appearance" }
            Note { text: "Choose the color of window borders, the Start menu and the taskbar." }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: ["#3a7bd5", "#1d9bd1", "#14a39a", "#37a33a", "#8cb51e", "#e3b012", "#e8792b", "#d9442b",
                            "#c4307a", "#a43dbf", "#6f4bd8", "#4a5bd1", "#5f7c8a", "#7a6a58", "#444a50", "#9aa5b1"]
                    delegate: Rectangle {
                        required property string modelData
                        width: 40; height: 40
                        radius: 4
                        border.width: Prefs.accentColor == modelData ? 3 : 1
                        border.color: Prefs.accentColor == modelData ? "#1e3287" : "#7a7a7a"
                        gradient: Gradient {
                            GradientStop { position: 0; color: Qt.lighter(modelData, 1.45) }
                            GradientStop { position: 0.5; color: modelData }
                            GradientStop { position: 1; color: Qt.darker(modelData, 1.25) }
                        }
                        Rectangle { x: 4; y: 4; width: parent.width - 8; height: parent.height / 2 - 4; radius: 2; color: Qt.rgba(1, 1, 1, 0.35) }
                        MouseArea { anchors.fill: parent; onClicked: Prefs.accentColor = modelData }
                    }
                }
            }
            CheckBox7 { text: "Enable transparency"; checked: Prefs.transparency; onToggled: (c) => Prefs.transparency = c }
            Row {
                spacing: 10
                VText { text: "Color intensity:"; anchors.verticalCenter: parent.verticalCenter; width: 110 }
                Slider7 { width: 260; from: 0.1; to: 0.9; stepSize: 0.01; value: Prefs.colorIntensity; onMoved: (v) => Prefs.colorIntensity = v }
            }
            CheckBox7 { text: "Animate windows and menus"; checked: Prefs.animations; onToggled: (c) => Prefs.animations = c }
            CheckBox7 { text: "Show desktop icons"; checked: Prefs.showDesktopIcons; onToggled: (c) => Prefs.showDesktopIcons = c }
            Item { width: 1; height: 8 }
            Button7 { text: "Restore defaults"; onClicked: Prefs.resetToDefaults() }
        }
    }

    Component {
        id: taskbarPage
        Column {
            spacing: 8
            Heading { text: "Taskbar and Start menu" }
            CheckBox7 { text: "Center taskbar icons"; checked: Prefs.taskbarCentered; onToggled: (c) => Prefs.taskbarCentered = c }
            CheckBox7 { text: "Use small taskbar buttons"; checked: Prefs.smallTaskbarIcons; onToggled: (c) => Prefs.smallTaskbarIcons = c }
            CheckBox7 { text: "Combine taskbar buttons"; checked: Prefs.combineButtons; onToggled: (c) => Prefs.combineButtons = c }
            SubHeading { text: "Clock" }
            CheckBox7 { text: "Use 24-hour time"; checked: Prefs.clock24h; onToggled: (c) => Prefs.clock24h = c }
            CheckBox7 { text: "Show seconds"; checked: Prefs.showSeconds; onToggled: (c) => Prefs.showSeconds = c }
            SubHeading { text: "Pinned programs" }
            Note { text: "Right-click a program in the Start menu or on the taskbar to pin or unpin it." }
            Repeater {
                model: { Prefs.pinnedApps; return Apps.appsForIds(Prefs.pinnedApps) }
                delegate: Row {
                    required property var modelData
                    spacing: 8
                    AppIcon { size: 20; name: modelData.iconName; anchors.verticalCenter: parent.verticalCenter }
                    VText { text: modelData.name; width: 240; anchors.verticalCenter: parent.verticalCenter }
                    Button7 { text: "Unpin"; onClicked: Prefs.unpin(modelData.desktopId) }
                }
            }
        }
    }

    Component {
        id: displayPage
        Column {
            spacing: 8
            Heading { text: "Display" }
            Note { text: "Resolution: " + Shell.screenWidth + " × " + Shell.screenHeight }
            SubHeading { text: "Brightness"; visible: Sys.hasBacklight }
            Slider7 { visible: Sys.hasBacklight; width: 300; from: 5; to: 100; value: Sys.brightness; onMoved: (v) => Sys.setBrightness(v) }
            SubHeading { text: "Night light" }
            Note { text: "Night light shows warmer colors to help you sleep." }
            CheckBox7 { text: "Turn on night light"; checked: Prefs.nightLight; onToggled: (c) => Prefs.nightLight = c }
            Row {
                spacing: 10
                VText { text: "Strength:"; anchors.verticalCenter: parent.verticalCenter; width: 80 }
                Slider7 { width: 260; from: 0.1; to: 1; stepSize: 0.01; value: Prefs.nightLightStrength; onMoved: (v) => Prefs.nightLightStrength = v }
            }
        }
    }

    Component {
        id: notificationsPage
        Column {
            spacing: 8
            Heading { text: "Notifications" }
            CheckBox7 { text: "Focus assist (hide notification banners)"; checked: Prefs.doNotDisturb; onToggled: (c) => Prefs.doNotDisturb = c }
            Note { text: Notifications.registered ? "Apps can show notifications." : "Another notification service is running, so app notifications are handled elsewhere." }
            Button7 { text: "Send a test notification"; onClicked: Notifications.post("Test notification", "This is how notifications look.", Theme.icon("vitrum")) }
        }
    }

    Component {
        id: compatPage
        Column {
            spacing: 8
            Heading { text: "Windows app support" }
            Note { text: "Open Windows programs (.exe), installers (.msi), batch files (.bat, .cmd), shortcuts (.lnk) and registry files (.reg) just by double-clicking them. Programs you install appear in the Start menu under “Windows Programs”." }
            Row {
                spacing: 10
                Rectangle { width: 12; height: 12; radius: 6; color: Compat.windowsAvailable ? "#37a33a" : "#d9442b"; anchors.verticalCenter: parent.verticalCenter }
                VText {
                    text: Compat.windowsAvailable ? "Windows app support is installed" + (Compat.runtimeVersion ? " (runtime " + Compat.runtimeVersion + ")" : "")
                                                  : "Windows app support is not installed"
                    font.bold: true
                }
            }
            Row {
                spacing: 8
                visible: !Compat.windowsAvailable
                Button7 { text: "Install Windows app support"; enabled: Compat.installCommand("windows").length > 0; onClicked: Compat.installRuntime("windows") }
                Button7 { text: "Check again"; onClicked: Compat.refresh() }
            }
            Note { visible: Compat.preparing; text: "Preparing Windows app support…" }
            Row {
                spacing: 8
                visible: Compat.windowsAvailable
                Button7 { text: "Open C: drive"; onClicked: Shell.openExplorer(Compat.prefix + "/drive_c") }
                Button7 { text: "Advanced configuration"; onClicked: Compat.openConfiguration() }
            }
            SubHeading { text: "Java programs (.jar)" }
            Row {
                spacing: 10
                Rectangle { width: 12; height: 12; radius: 6; color: Compat.javaAvailable ? "#37a33a" : "#d9442b"; anchors.verticalCenter: parent.verticalCenter }
                VText { text: Compat.javaAvailable ? "Java runtime is installed" : "Java runtime is not installed"; font.bold: true }
            }
            Button7 { visible: !Compat.javaAvailable; text: "Install Java runtime"; enabled: Compat.installCommand("java").length > 0; onClicked: Compat.installRuntime("java") }
        }
    }

    Component {
        id: timePage
        Column {
            spacing: 8
            Heading { text: "Date and time" }
            property date now: new Date()
            Timer { interval: 1000; running: true; repeat: true; onTriggered: parent.now = new Date() }
            VText { text: Qt.formatDateTime(parent.now, "dddd, MMMM d, yyyy  " + (Prefs.clock24h ? "HH:mm:ss" : "h:mm:ss AP")); font.pixelSize: Theme.fontSizeLarge }
            CheckBox7 { text: "Use 24-hour time"; checked: Prefs.clock24h; onToggled: (c) => Prefs.clock24h = c }
            CheckBox7 { text: "Show seconds on the taskbar"; checked: Prefs.showSeconds; onToggled: (c) => Prefs.showSeconds = c }
            Note { text: "The system clock is set automatically from the internet." }
        }
    }

    Component {
        id: aboutPage
        AboutContent {}
    }
}
