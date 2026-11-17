import QtQuick
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// Everything drawn on the output: wallpaper, desktop, windows and the shell
// surfaces layered above them.
Item {
    id: screen
    property var compositor: null
    property var window: null
    property int nextUid: 1

    Component.onCompleted: {
        Shell.root = screen
        Shell.compositor = compositor
        Shell.blurTexture = blurTexture
        Shell.screenWidth = width
        Shell.screenHeight = height
        desktopIcons.forceActiveFocus()
        if (!Session.demo)
            welcome.start()
    }
    onWidthChanged: Shell.screenWidth = width
    onHeightChanged: Shell.screenHeight = height

    // ---- background + blurred copy for glass
    Wallpaper { id: wallpaper; anchors.fill: parent }
    ShaderEffectSource {
        id: wallSmall
        sourceItem: wallpaper
        width: Math.max(1, Math.round(screen.width / 5))
        height: Math.max(1, Math.round(screen.height / 5))
        textureSize: Qt.size(width, height)
        visible: false
        smooth: true
    }
    FastBlur {
        id: blurItem
        width: wallSmall.width
        height: wallSmall.height
        source: wallSmall
        radius: 28
        transparentBorder: false
        visible: false
    }
    ShaderEffectSource {
        id: blurTexture
        width: screen.width
        height: screen.height
        sourceItem: blurItem
        visible: false
        smooth: true
    }

    DesktopIcons {
        id: desktopIcons
        anchors.fill: parent
        anchors.bottomMargin: Theme.taskbarHeight
        visible: Prefs.showDesktopIcons
        focus: true
    }
    Connections {
        target: Shell
        function onFocusShell() { desktopIcons.forceActiveFocus() }
        function onOpenInternal(kind, props) { screen.openInternal(kind, props) }
        function onScreenshotRequested() { screen.takeScreenshot(false) }
    }
    Connections {
        target: Apps
        function onInternalRequested(kind, file) {
            Shell.closePopups()
            if (kind === "explorer") Shell.openExplorer(file)
            else if (kind === "settings") Shell.openSettings("")
            else screen.openInternal(kind, file ? { path: file } : {})
        }
    }

    // ---- windows
    Item {
        id: windowLayer
        anchors.fill: parent
        SnapPreview { z: Shell.activeWindow ? Shell.activeWindow.z - 0.5 : 5 }
    }

    Component { id: frameComponent; WindowFrame {} }
    Component { id: settingsApp; SettingsApp {} }
    Component { id: explorerApp; ExplorerApp {} }
    Component { id: runApp; RunDialog {} }
    Component { id: taskManagerApp; TaskManagerApp {} }
    Component { id: aboutApp; AboutDialog {} }
    Component { id: propertiesApp; PropertiesDialog {} }
    Component { id: notepadApp; NotepadApp {} }
    Component { id: photosApp; PhotoViewerApp {} }
    Component { id: messageApp; MessageDialog {} }
    Component { id: calculatorApp; CalculatorApp {} }
    Component { id: paintApp; PaintApp {} }
    Component { id: stickyNotesApp; StickyNotesApp {} }
    Component { id: stickyConfirmApp; StickyNoteConfirm {} }
    Component { id: snippingToolApp; SnippingToolApp {} }

    readonly property var internalSpecs: ({
        settings:    { component: settingsApp, title: "Control Panel", icon: Theme.icon("settings"), w: 860, h: 580, single: true },
        explorer:    { component: explorerApp, title: "Explorer", icon: Theme.icon("folder"), w: 880, h: 560 },
        run:         { component: runApp, title: "Run", icon: Theme.icon("run"), w: 410, h: 186, single: true, resizable: false },
        taskmanager: { component: taskManagerApp, title: "Task Manager", icon: Theme.icon("taskmanager"), w: 520, h: 520, single: true },
        about:       { component: aboutApp, title: "About Vitrum", icon: Theme.icon("about"), w: 470, h: 400, single: true, resizable: false },
        properties:  { component: propertiesApp, title: "Properties", icon: Theme.icon("properties"), w: 380, h: 470, resizable: false },
        notepad:     { component: notepadApp, title: "Untitled - Notepad", icon: Theme.icon("notepad"), w: 720, h: 500 },
        photos:      { component: photosApp, title: "Photo Viewer", icon: Theme.icon("image-file"), w: 820, h: 600 },
        message:     { component: messageApp, title: "Vitrum", icon: Theme.icon("about"), w: 420, h: 170, resizable: false },
        calculator:  { component: calculatorApp, title: "Calculator", icon: Theme.icon("calculator"), w: 212, h: 288, resizable: false },
        paint:       { component: paintApp, title: "Untitled - Paint", icon: Theme.icon("paint"), w: 900, h: 640 },
        stickynotes: { component: stickyNotesApp, title: "Sticky Notes", icon: Theme.icon("stickynotes"), w: 200, h: 200, resizable: false, frameless: true },
        stickyconfirm: { component: stickyConfirmApp, title: "Sticky Notes", icon: Theme.icon("stickynotes"), w: 380, h: 124, resizable: false },
        snippingtool:{ component: snippingToolApp, title: "Snipping Tool", icon: Theme.icon("snippingtool"), w: 420, h: 96 }
    })

    function createClientWindow(xdgSurface) {
        const w = frameComponent.createObject(windowLayer, { xdgSurface: xdgSurface, uid: "c" + (nextUid++) })
        Shell.addWindow(w)
        return w
    }

    function openInternal(kind, props) {
        const spec = internalSpecs[kind]
        if (!spec)
            return null
        if (spec.single) {
            const existing = Shell.windows.find(w => w.internalKind === kind && !w.closing)
            if (existing) {
                if (existing.internalItem)
                    for (const k in props)
                        if (existing.internalItem.hasOwnProperty(k))
                            existing.internalItem[k] = props[k]
                Shell.activate(existing)
                return existing
            }
        }
        const w = frameComponent.createObject(windowLayer, {
            internalComponent: spec.component,
            internalKind: kind,
            internalTitle: props.title || spec.title,
            internalIcon: spec.icon,
            internalWidth: props.width || spec.w,
            internalHeight: props.height || spec.h,
            internalResizable: spec.resizable !== false,
            internalMaximizable: spec.resizable !== false,
            internalFrameless: spec.frameless === true,
            internalProps: props,
            uid: "i" + (nextUid++)
        })
        Shell.addWindow(w)
        return w
    }

    function takeScreenshot(windowOnly) {
        const path = Session.newScreenshotPath()
        let crop = Qt.rect(0, 0, 0, 0)
        const w = Shell.activeWindow
        if (windowOnly && w)
            crop = Qt.rect(w.x, w.y, w.width, w.height)
        Qt.callLater(() => {
            if (Session.saveScreenshot(screen.window, path, crop))
                Shell.notify("Screenshot saved", path.replace(Files.home, "~"), Theme.icon("image-file"))
        })
    }

    // ---- global shortcuts
    Connections {
        target: Shortcuts
        function onShortcut(name) { screen.handleShortcut(name) }
    }
    Binding { target: Shortcuts; property: "locked"; value: Shell.locked }

    function handleShortcut(name) {
        if (Shell.locked)
            return
        if (Shell.secureScreen && name !== "secureAttention")
            return
        const w = Shell.activeWindow
        if (name.indexOf("taskbar:") === 0) {
            Shell.closePopups()
            taskbar.activateIndex(parseInt(name.substring(8)))
            return
        }
        switch (name) {
        case "start": Shell.toggleStart(); break
        case "search": if (!Shell.startOpen) Shell.toggleStart(); break
        case "showDesktop": Shell.closePopups(); Shell.toggleDesktop(); break
        case "minimizeAll": Shell.closePopups(); Shell.minimizeAll(); break
        case "minimizeOthers": Shell.minimizeOthers(); break
        case "explorer": Shell.openExplorer(""); break
        case "run": Shell.openRun(); break
        case "lock": Shell.lock(); break
        case "actionCenter": Shell.toggleActionCenter(); break
        case "settings": Shell.openSettings(""); break
        case "about": Shell.openAbout(); break
        case "quickLink": Shell.showQuickLinks(4, Shell.screenHeight - Theme.taskbarHeight); break
        case "taskManager": Shell.openTaskManager(); break
        case "terminal": Launcher.openTerminal(""); break
        case "secureAttention": Shell.closePopups(); Shell.secureScreen = !Shell.secureScreen; break
        case "screenshot": screen.takeScreenshot(false); break
        case "screenshotWindow": screen.takeScreenshot(true); break
        case "switchNext": Shell.switchStep(1); break
        case "switchPrev": Shell.switchStep(-1); break
        case "switchCommit": Shell.switchCommit(); break
        case "switchCancel": Shell.switcherOpen = false; break
        case "close": if (w) w.close(); break
        case "volumeUp": Sys.setVolume(Sys.volume + 5); break
        case "volumeDown": Sys.setVolume(Sys.volume - 5); break
        case "volumeMute": Sys.toggleMute(); break
        case "brightnessUp": Sys.setBrightness(Sys.brightness + 10); break
        case "brightnessDown": Sys.setBrightness(Sys.brightness - 10); break
        case "maximize": if (w) w.maximize(); break
        case "restoreOrMinimize":
            if (w) { if (w.maximized || w.tile !== "") w.restore(); else Shell.minimize(w) }
            break
        case "snapLeft":
            if (w) { if (w.tile === "right") w.restore(); else w.snap("left") }
            break
        case "snapRight":
            if (w) { if (w.tile === "left") w.restore(); else w.snap("right") }
            break
        case "snapLayouts":
            if (w && w.resizable) {
                Shell.snapLayoutsAnchor = Qt.point(w.x + w.width - 60, w.y + Theme.titleHeight)
                Shell.snapLayoutsFor = w
            }
            break
        }
    }

    // ---- shell surfaces
    MouseArea { // click-away dismissal for menus and flyouts
        anchors.fill: parent
        visible: Shell.anyPopupOpen
        acceptedButtons: Qt.AllButtons
        onPressed: { Shell.closePopups(); Shell.restoreFocus() }
    }
    Taskbar {
        id: taskbar
        width: parent.width
        y: parent.height - height
        visible: !Shell.taskbarHidden
    }
    Thumbnails { taskbar: taskbar }
    StartMenu {}
    ClockFlyout {}
    VolumeFlyout {}
    NetworkFlyout {}
    ActionCenter {}
    SnapLayouts {}
    Toasts {}
    AltTab {}
    ContextMenu {}
    TooltipLayer {}
    LockScreen {}
    SecureScreen {}

    Rectangle { // night light
        anchors.fill: parent
        color: "#ff8a1e"
        opacity: Prefs.nightLight ? Prefs.nightLightStrength * 0.32 : 0
        visible: opacity > 0
        enabled: false
        Behavior on opacity { NumberAnimation { duration: 600 } }
    }

    Timer {
        id: welcome
        interval: 1500
        onTriggered: {
            if (!Prefs.welcomeShown || Session.env("VITRUM_WELCOME") === "1") {
                Prefs.welcomeShown = true
                Shell.notify("Welcome to Vitrum", "Press the Start button or the Windows key to get started.", Theme.icon("vitrum"))
            }
        }
    }

    // ---- scripted tour used by CI to produce screenshots
    DemoDriver {
        enabled: Session.demo
        screen: screen
        taskbar: taskbar
    }
}
