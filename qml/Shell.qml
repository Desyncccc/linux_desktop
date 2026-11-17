pragma Singleton
import QtQuick
import Vitrum
import Vitrum.Core

// Shared shell state and window-management policy.
QtObject {
    id: shell

    // ---- set up by Main.qml
    property var compositor: null
    property Item root: null
    property Item blurTexture: null
    property real screenWidth: 1366
    property real screenHeight: 768
    readonly property real taskbarHeight: taskbarHidden ? 0 : Theme.taskbarHeight
    readonly property rect workArea: Qt.rect(0, 0, screenWidth, screenHeight - Theme.taskbarHeight)

    // ---- windows
    property var windows: []          // creation order (taskbar order)
    property var focusOrder: []       // most recent first (Alt+Tab order)
    property Item activeWindow: null
    property int topZ: 10
    property int revision: 0          // bumped when window metadata changes
    readonly property bool taskbarHidden: activeWindow !== null && activeWindow.fullscreen && !activeWindow.minimized

    // ---- shell surfaces
    property bool startOpen: false
    property bool startAllPrograms: false
    property bool actionCenterOpen: false
    property string flyout: ""        // "clock" | "volume" | "network" | ""
    property bool locked: false
    property bool secureScreen: false
    property bool switcherOpen: false
    property int switcherIndex: 0
    property bool showingDesktop: false
    property var desktopHidden: []
    property bool menuOpen: false
    property Item snapLayoutsFor: null
    property point snapLayoutsAnchor: Qt.point(0, 0)

    // Aero Peek
    property Item peekWindow: null
    property bool peekDesktop: false
    readonly property bool peeking: peekWindow !== null || peekDesktop

    // Snap preview while dragging
    property string snapTarget: ""
    readonly property rect snapRect: tileRect(snapTarget)

    readonly property bool anyPopupOpen: startOpen || actionCenterOpen || flyout !== "" || menuOpen
                                         || snapLayoutsFor !== null

    // Flyout anchor, taskbar thumbnails and tooltips
    property real flyoutX: 0
    property string thumbKey: ""
    property real thumbX: 0
    property bool thumbHideRequested: false
    property string tooltipText: ""
    property point tooltipPos: Qt.point(0, 0)

    function showThumbnails(key, x) {
        if (startOpen || menuOpen)
            return
        thumbKey = key
        thumbX = x
        thumbHideRequested = false
    }
    function hideThumbnailsSoon() { thumbHideRequested = true }
    function hideThumbnails() {
        thumbKey = ""
        thumbHideRequested = false
        peekWindow = null
    }
    function showTooltip(text, x, y) {
        tooltipText = text
        tooltipPos = Qt.point(x, y)
    }
    function hideTooltip() { tooltipText = "" }

    function showQuickLinks(x, y) {
        const entries = [
            { text: "Apps and programs", icon: Theme.icon("apps"), action: () => { shell.startOpen = true; shell.startAllPrograms = true } },
            { text: "System", icon: Theme.icon("about"), action: () => shell.openAbout() },
            { text: "Task Manager", icon: Theme.icon("taskmanager"), action: () => shell.openTaskManager() },
            { text: "Control Panel", icon: Theme.icon("settings"), action: () => shell.openSettings("") },
            { text: "File Explorer", icon: Theme.icon("folder"), action: () => shell.openExplorer("") },
            { text: "Search", icon: Theme.icon("search"), action: () => shell.toggleStart() },
            { text: "Run", icon: Theme.icon("run"), action: () => shell.openRun() },
            { text: "Terminal", icon: Theme.icon("terminal"), action: () => Launcher.openTerminal("") },
            { separator: true },
            { text: "Lock", icon: Theme.icon("lock"), action: () => shell.lock() },
            { text: "Sign out", icon: Theme.icon("logout"), action: () => shell.logout() },
            { text: "Sleep", icon: Theme.icon("sleep"), action: () => Sys.suspend() },
            { text: "Restart", icon: Theme.icon("restart"), action: () => Sys.reboot() },
            { text: "Shut down", icon: Theme.icon("power"), action: () => Sys.powerOff() },
            { separator: true },
            { text: "Desktop", icon: Theme.icon("desktop"), action: () => shell.toggleDesktop() }
        ]
        showMenu(entries, x, y - entries.length * 21)
    }

    signal menuRequested(var entries, real x, real y)
    signal openInternal(string kind, var props)
    signal notify(string summary, string body, string icon)
    signal focusShell()
    signal screenshotRequested()
    property bool pointerOnClient: false

    function closePopups() {
        startOpen = false
        startAllPrograms = false
        actionCenterOpen = false
        flyout = ""
        menuOpen = false
        snapLayoutsFor = null
    }

    function toggleStart() {
        const open = !startOpen
        closePopups()
        startOpen = open
        if (!open)
            restoreFocus()
    }

    function toggleActionCenter() {
        const open = !actionCenterOpen
        closePopups()
        actionCenterOpen = open
    }

    function toggleFlyout(name) {
        const open = flyout !== name
        closePopups()
        flyout = open ? name : ""
    }

    function showMenu(entries, x, y) {
        closePopups()
        menuOpen = true
        menuRequested(entries, x, y)
    }

    // ---- window bookkeeping
    function addWindow(w) {
        windows = windows.concat([w])
        activate(w)
    }

    function removeWindow(w) {
        windows = windows.filter(x => x !== w)
        focusOrder = focusOrder.filter(x => x !== w)
        desktopHidden = desktopHidden.filter(x => x !== w)
        if (peekWindow === w)
            peekWindow = null
        if (snapLayoutsFor === w)
            snapLayoutsFor = null
        if (activeWindow === w) {
            activeWindow = null
            activateNext()
        }
    }

    function activate(w) {
        if (!w || w.closing)
            return
        if (w.minimized)
            w.minimized = false
        w.z = ++topZ
        activeWindow = w
        focusOrder = [w].concat(focusOrder.filter(x => x !== w))
        showingDesktop = false
        desktopHidden = []
        w.takeFocus()
    }

    function activateNext() {
        const candidates = focusOrder.filter(x => !x.minimized && !x.closing)
        if (candidates.length > 0)
            activate(candidates[0])
        else {
            activeWindow = null
            focusShell()
        }
    }

    function deactivate() {
        activeWindow = null
        focusShell()
    }

    function restoreFocus() {
        if (activeWindow && !activeWindow.minimized)
            activeWindow.takeFocus()
        else
            focusShell()
    }

    function minimize(w) {
        if (!w)
            return
        w.minimized = true
        if (activeWindow === w) {
            activeWindow = null
            activateNext()
        }
    }

    function windowForSurface(surface) {
        for (let i = 0; i < windows.length; ++i)
            if (windows[i].surface === surface)
                return windows[i]
        return null
    }

    function windowsForGroup(key) {
        return windows.filter(w => w.groupKey === key && !w.closing)
    }

    function toggleDesktop() {
        if (showingDesktop) {
            const toRestore = desktopHidden
            showingDesktop = false
            desktopHidden = []
            for (let i = toRestore.length - 1; i >= 0; --i)
                activate(toRestore[i])
            return
        }
        const visible = focusOrder.filter(w => !w.minimized && !w.closing)
        for (let i = 0; i < visible.length; ++i)
            visible[i].minimized = true
        activeWindow = null
        desktopHidden = visible
        showingDesktop = true
        focusShell()
    }

    function minimizeAll() {
        for (let i = 0; i < windows.length; ++i)
            windows[i].minimized = true
        activeWindow = null
        focusShell()
    }

    function minimizeOthers() {
        for (let i = 0; i < windows.length; ++i)
            if (windows[i] !== activeWindow)
                windows[i].minimized = true
    }

    // ---- Alt+Tab
    function switchStep(delta) {
        const list = focusOrder.filter(w => !w.closing)
        if (list.length === 0)
            return
        closePopups()
        if (!switcherOpen) {
            switcherOpen = true
            switcherIndex = list.length > 1 ? (delta > 0 ? 1 : list.length - 1) : 0
        } else {
            switcherIndex = (switcherIndex + delta + list.length) % list.length
        }
    }

    function switchCommit() {
        if (!switcherOpen)
            return
        const list = focusOrder.filter(w => !w.closing)
        switcherOpen = false
        if (switcherIndex >= 0 && switcherIndex < list.length)
            activate(list[switcherIndex])
    }

    // ---- Snap
    function tileRect(name) {
        const a = workArea
        const hw = Math.round(a.width / 2), hh = Math.round(a.height / 2)
        const tw = Math.round(a.width / 3)
        switch (name) {
        case "max": return a
        case "left": return Qt.rect(a.x, a.y, hw, a.height)
        case "right": return Qt.rect(a.x + hw, a.y, a.width - hw, a.height)
        case "tl": return Qt.rect(a.x, a.y, hw, hh)
        case "tr": return Qt.rect(a.x + hw, a.y, a.width - hw, hh)
        case "bl": return Qt.rect(a.x, a.y + hh, hw, a.height - hh)
        case "br": return Qt.rect(a.x + hw, a.y + hh, a.width - hw, a.height - hh)
        case "t1": return Qt.rect(a.x, a.y, tw, a.height)
        case "t2": return Qt.rect(a.x + tw, a.y, tw, a.height)
        case "t3": return Qt.rect(a.x + 2 * tw, a.y, a.width - 2 * tw, a.height)
        case "l23": return Qt.rect(a.x, a.y, 2 * tw, a.height)
        case "r13": return Qt.rect(a.x + 2 * tw, a.y, a.width - 2 * tw, a.height)
        }
        return Qt.rect(0, 0, 0, 0)
    }

    function snapTargetAt(x, y) {
        const edge = 4, corner = 48
        const a = workArea
        if (x <= a.x + edge) {
            if (y < a.y + corner) return "tl"
            if (y > a.y + a.height - corner) return "bl"
            return "left"
        }
        if (x >= a.x + a.width - edge) {
            if (y < a.y + corner) return "tr"
            if (y > a.y + a.height - corner) return "br"
            return "right"
        }
        if (y <= a.y + 2)
            return "max"
        return ""
    }

    // ---- Internal apps
    function openSettings(page) { closePopups(); openInternal("settings", { page: page || "" }) }
    function openExplorer(path) { closePopups(); openInternal("explorer", { path: path || "" }) }
    function openRun() { closePopups(); openInternal("run", {}) }
    function openTaskManager() { closePopups(); openInternal("taskmanager", {}) }
    function openAbout() { closePopups(); openInternal("about", {}) }
    function openProperties(path) { closePopups(); openInternal("properties", { path: path }) }

    // Opens a file the way double-clicking it should: folders in Explorer,
    // pictures and text in the built-in viewers, programs (including Windows
    // .exe/.msi/.bat and Java .jar) directly, everything else with its app.
    function openFile(path) {
        closePopups()
        if (Files.isDir(path))
            return openExplorer(path)
        if (path.endsWith(".desktop"))
            return Files.launchDesktopFile(path)
        if (Files.isImage(path))
            return openInternal("photos", { path: path })
        if (Files.isText(path))
            return openInternal("notepad", { path: path })
        const err = Launcher.openFile(path)
        if (err === "missing-windows" || err === "missing-java")
            openInternal("message", { kind: err, file: path })
        else if (err.length > 0)
            notify("Can't open this file", Files.fileName(path), "dialog-error")
    }

    // Programs being started: a second click while one is still starting
    // (slow virtual machines) would start a second copy. Browsers in
    // particular then fail on their half-created profile.
    property var launching: ({})
    function launchApp(desktopId) {
        closePopups()
        const now = Date.now()
        const started = launching[desktopId] || 0
        const internalApp = desktopId.indexOf("vitrum-builtin-") === 0
        if (!internalApp && now - started < 8000 && windowsForGroup(desktopId).length === 0)
            return
        const l = Object.assign({}, launching)
        l[desktopId] = now
        launching = l
        if (Apps.launch(desktopId))
            Prefs.recordLaunch(desktopId)
        else
            notify("Couldn't start the program", Apps.get(desktopId).name || desktopId, "dialog-error")
    }

    function lock() {
        closePopups()
        switcherOpen = false
        if (!Auth.available) {
            notify("Lock is unavailable", "This build of Vitrum was compiled without PAM.", "dialog-warning")
            return
        }
        locked = true
        secureScreen = false
    }

    function logout() { Session.logout() }
}
