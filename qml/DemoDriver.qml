import QtQuick
import Vitrum
import Vitrum.Core

// Scripted tour (vitrum --demo DIR): drives the shell through its main
// surfaces and saves a screenshot of each. Used by CI as a smoke test.
Item {
    id: demo
    property bool enabled: false
    property Item screen: null
    property Item taskbar: null
    property int index: 0
    property int shotNo: 1
    property var explorerWin: null
    property var settingsWin: null

    function shot(name) {
        const n = (shotNo < 10 ? "0" : "") + shotNo
        shotNo++
        const path = Session.demoDir + "/" + n + "-" + name + ".png"
        if (!Session.saveScreenshot(screen.window, path))
            console.warn("demo: failed to save", path)
        else
            console.info("demo: saved", path)
    }

    // [delay before action (ms), action, screenshot name or ""]
    readonly property var steps: [
        [2200, () => {}, "desktop"],
        [300, () => { if (Session.demoClient.length) Launcher.runCommand(Session.demoClient) }, ""],
        [Session.demoClient.length ? 3500 : 10, () => {}, Session.demoClient.length ? "client-window" : ""],
        [300, () => Shell.toggleStart(), ""],
        [700, () => {}, "start-menu"],
        [100, () => { Shell.startAllPrograms = true }, ""],
        [600, () => {}, "start-all-programs"],
        [100, () => { Shell.closePopups(); explorerWin = screen.openInternal("explorer", { path: Files.home }) }, ""],
        [900, () => {}, "explorer"],
        [100, () => { settingsWin = screen.openInternal("settings", { page: "personalize" }) }, ""],
        [900, () => {}, "settings"],
        [100, () => { if (explorerWin) explorerWin.snap("left"); if (settingsWin) settingsWin.snap("right") }, ""],
        [900, () => {}, "snapped"],
        [100, () => { Notifications.post("Backup complete", "Your files were backed up to Documents.", Theme.icon("drive")) }, ""],
        [900, () => {}, "toast"],
        [100, () => Shell.toggleActionCenter(), ""],
        [800, () => {}, "action-center"],
        [100, () => { Shell.closePopups(); Shell.flyoutX = Shell.screenWidth - 90; Shell.toggleFlyout("clock") }, ""],
        [600, () => {}, "clock"],
        [100, () => { Shell.closePopups(); Shell.switchStep(1) }, ""],
        [900, () => {}, "alt-tab"],
        [100, () => { Shell.switchCommit() }, ""],
        [100, () => { if (settingsWin) settingsWin.restore(); if (settingsWin) settingsWin.internalItem.page = "compat" }, ""],
        [700, () => {}, "windows-app-support"],
        [100, () => { screen.openInternal("notepad", {}) }, ""],
        [700, () => {}, "notepad"],
        [100, () => { screen.openInternal("message", { kind: "missing-windows", file: Files.downloads + "/setup.exe" }) }, ""],
        [700, () => {}, "exe-prompt"],
        [100, () => { Shell.activateNext(); if (settingsWin) { Shell.activate(settingsWin); settingsWin.internalItem.page = "personalize" } Prefs.theme = "modern"; Prefs.taskbarCentered = true }, ""],
        [900, () => {}, "theme-modern"],
        [100, () => { Prefs.theme = "basic"; Prefs.taskbarCentered = false }, ""],
        [900, () => {}, "theme-basic"],
        [100, () => { Prefs.theme = "aero"; Shell.minimizeAll(); Prefs.taskbarCentered = true; Prefs.wallpaper = "builtin:dusk"; Prefs.accentColor = "#a43dbf"; Shell.toggleStart() }, ""],
        [900, () => {}, "centered-taskbar"],
        [100, () => { Shell.closePopups(); Prefs.resetToDefaults(); Shell.lock() }, ""],
        [900, () => {}, "lock-screen"],
        [100, () => { Shell.secureScreen = false }, ""],
        [400, () => { Session.quit(0) }, ""]
    ]

    Timer {
        id: timer
        running: demo.enabled && demo.index < demo.steps.length
        interval: demo.index < demo.steps.length ? demo.steps[demo.index][0] : 100
        onTriggered: {
            const s = demo.steps[demo.index]
            s[1]()
            if (s[2].length > 0)
                demo.shot(s[2])
            demo.index++
        }
    }
    Timer { // safety net
        running: demo.enabled
        interval: 120000
        onTriggered: { console.warn("demo: timed out"); Session.quit(4) }
    }
}
