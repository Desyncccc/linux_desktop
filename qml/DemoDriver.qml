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
    property var calcWin: null

    // Calculator: engine self-test plus the keyboard character map.
    function checkCalculator() {
        const calc = calcWin.internalItem
        const r = calc.engine.selfTest()
        for (const f of r.failures)
            console.warn("demo: calculator check failed:", f)
        calc.engine.press("c")
        const keys = "12+3*2=", want = "30"
        for (let i = 0; i < keys.length; i++)
            calc.press(calc.charCommand(keys.charAt(i)))
        if (calc.engine.display !== want)
            console.warn("demo: calculator keys", keys, "gave", calc.engine.display, "expected", want)
        calc.engine.run("[c]1234.5")
        calc.copy()
        calc.engine.run("[c]")
        calc.paste()
        if (calc.engine.display !== "1234.5")
            console.warn("demo: calculator copy/paste gave", calc.engine.display)
        console.info("demo: calculator self-test", r.total - r.failures.length, "/", r.total, "passed")
    }
    function stickyWindows() {
        return Shell.windows.filter(w => w.internalKind === "stickynotes" && !w.closing)
    }
    // Every saved note must come back as its own window with its text and colour.
    function checkStickyRestore() {
        const wins = stickyWindows()
        const store = wins.length ? wins[0].internalItem.readStore() : { notes: [] }
        let ok = wins.length === store.notes.length && wins.length >= 2
        for (const n of store.notes) {
            const w = wins.find(x => x.internalItem.noteId === n.id)
            if (!w || w.internalItem.text !== n.text || w.internalItem.noteColor !== n.color)
                ok = false
        }
        if (!ok)
            console.warn("demo: sticky notes not restored:", wins.length, "windows for", store.notes.length, "saved notes")
        else
            console.info("demo: sticky notes restored", wins.length, "notes")
    }

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
        [100, () => { if (explorerWin) { explorerWin.internalItem.navigate(Files.documents, true); explorerWin.internalItem.selectIndex(0, 0) } }, ""],
        [700, () => {}, "explorer-documents"],
        [100, () => { if (explorerWin) { explorerWin.internalItem.navigate(Files.pictures, true); explorerWin.internalItem.previewPaneShown = true } }, ""],
        [700, () => {}, "explorer-pictures"],
        [100, () => { if (explorerWin) { explorerWin.internalItem.previewPaneShown = false; explorerWin.internalItem.navigate("::computer", true) } }, ""],
        [700, () => {}, "explorer-computer"],
        [100, () => { if (explorerWin) { explorerWin.internalItem.navigate(Files.home, true); explorerWin.internalItem.setView("tiles"); explorerWin.internalItem.menuBarPinned = true } }, ""],
        [700, () => {}, "explorer-tiles"],
        [100, () => { if (explorerWin) { const e = explorerWin.internalItem; e.menuBarPinned = false; e.setView("details"); e.navigate(Files.home, true) } }, ""],
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
        [100, () => { const c = screen.openInternal("calculator", {}); if (c) { c.x = 900; c.y = 120 } }, ""],
        [100, () => { screen.openInternal("notepad", {}) }, ""],
        [700, () => {}, "notepad"],
        [100, () => { screen.openInternal("message", { kind: "missing-windows", file: Files.downloads + "/setup.exe" }) }, ""],
        [700, () => {}, "exe-prompt"],
        [100, () => { calcWin = screen.openInternal("calculator", {}); calcWin.x = 380; calcWin.y = 120 }, ""],
        [600, () => { checkCalculator(); calcWin.internalItem.engine.run("[c]42[ms][c]125+75*3") }, "calculator"],
        [100, () => { calcWin.internalItem.mode = "scientific"; calcWin.internalItem.engine.run("2*(3+4") }, ""],
        [600, () => {}, "calculator-scientific"],
        [100, () => { const c = calcWin.internalItem; c.mode = "standard"; c.showHistory = true
                      c.engine.run("0.1+0.2=1/3*3=50+10%=7[sqrt]") }, ""],
        [600, () => {}, "calculator-history"],
        [100, () => { calcWin.internalItem.showHistory = false; calcWin.close(); screen.openInternal("stickynotes", {}) }, ""],
        [600, () => { const n = stickyWindows()[0]; n.x = 820; n.y = 70; n.internalWidth = 230; n.internalHeight = 210
                      n.internalItem.text = "Call the garage about the brakes\n\nBuy milk, bread, coffee"; n.internalItem.newNote() }, ""],
        [600, () => { const n = stickyWindows()[1]; n.x = 1080; n.y = 150
                      n.internalItem.text = "Team lunch Friday 12:30"; n.internalItem.setColor("blue") }, ""],
        [500, () => {}, "sticky-notes"],
        [100, () => { stickyWindows()[1].internalItem.showMenu(1140, 260) }, ""],
        [500, () => {}, "sticky-notes-menu"],
        [100, () => { Shell.closePopups(); stickyWindows()[1].internalItem.askDelete() }, ""],
        [600, () => {}, "sticky-notes-delete"],
        [100, () => { Shell.windows.filter(w => w.internalKind === "stickyconfirm").forEach(w => w.internalItem.answer(false))
                      stickyWindows().forEach(w => w.close()) }, ""],
        [700, () => { screen.openInternal("stickynotes", {}) }, ""],
        [900, () => { checkStickyRestore(); screen.openInternal("stickynotes", {}) }, "sticky-notes-restored"],
        [600, () => { // opening it again while running adds no window; deleting removes the saved note
            const wins = stickyWindows()
            if (wins.length !== 2)
                console.warn("demo: sticky notes relaunch left", wins.length, "windows")
            wins[1].internalItem.deleteNote()
            if (wins[0].internalItem.readStore().notes.length !== 1)
                console.warn("demo: sticky note was not deleted from the store")
            wins[0].close() }, ""],
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
