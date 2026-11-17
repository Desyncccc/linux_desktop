import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// Snipping Tool: a small toolbar window that freezes the screen under a
// white wash, lets you drag out a free-form, rectangular, window or
// full-screen snip, then turns into a mark-up window with pen, highlighter
// and eraser.
FocusScope {
    id: snip
    property var frame: null
    property string path: ""
    property string mode: "rect"           // free | rect | window | full
    property string phase: "idle"          // idle | capturing | editor
    property var overlay: null
    property string inkTool: "pen"         // pen | highlighter | eraser
    property color penColor: "#e2231a"
    property string savedPath: ""
    property bool closeConfirmed: false
    property var pendingAction: null

    // Options
    property bool hideInstructions: false
    property bool copyToClipboard: true
    property bool promptToSave: true
    property bool showOverlay: true
    property bool selectionInk: true
    property color selectionInkColor: "#e2231a"

    readonly property var modes: [["free", "Free-form Snip"], ["rect", "Rectangular Snip"], ["window", "Window Snip"], ["full", "Full-screen Snip"]]
    readonly property var pens: [["Red Pen", "#e2231a"], ["Blue Pen", "#1f5fcf"], ["Black Pen", "#111111"]]
    readonly property bool hasSnip: phase === "editor"
    readonly property bool unsaved: hasSnip && editor.modified

    Component.onCompleted: { updateTitle(); forceActiveFocus() }
    Component.onDestruction: if (overlay) overlay.destroy()
    onFrameChanged: {
        updateTitle()
        updateResizable()
        if (frame)
            Qt.callLater(keepOnScreen)
    }
    onHasSnipChanged: updateResizable()
    // The toolbar window has a fixed size; the mark-up window can be resized.
    function updateResizable() {
        if (!frame)
            return
        frame.internalResizable = hasSnip
        frame.internalMaximizable = hasSnip
    }
    onHideInstructionsChanged: if (!hasSnip && frame) frame.internalHeight = hideInstructions ? 34 : 96
    function updateTitle() { if (frame) frame.internalTitle = "Snipping Tool" }
    function keepOnScreen() {
        const a = Shell.workArea
        if (!frame)
            return
        if (frame.x + frame.width > a.x + a.width || frame.x < a.x)
            frame.x = Math.max(a.x, a.x + (a.width - frame.width) / 2)
        if (frame.y + frame.height > a.y + a.height)
            frame.y = Math.max(a.y, a.y + (a.height - frame.height) / 2)
    }

    // ================================================================ capture
    function newSnip(m) {
        if (m)
            mode = m
        Shell.closePopups()
        optionsDialog.open = false
        if (overlay)
            return
        phase = "capturing"
        if (frame && !frame.minimized)
            Shell.minimize(frame)
        // Let the window fade out of the picture before freezing the screen.
        hideTimer.start()
    }
    Timer {
        id: hideTimer
        interval: Theme.anim(220) + 140
        onTriggered: snip.beginCapture()
    }
    function beginCapture() {
        const o = overlayComponent.createObject(Shell.root, { mode: snip.mode })
        if (!o.shot.grabWindow(Shell.root.window)) {
            o.destroy()
            cancelCapture()
            return
        }
        overlay = o
        o.visible = true
        o.forceActiveFocus()
        if (mode === "full")
            finishCapture(Qt.rect(0, 0, o.shot.imageWidth, o.shot.imageHeight), [])
    }
    function cancelCapture() {
        if (overlay) {
            overlay.destroy()
            overlay = null
        }
        phase = editor.imageWidth > 1 && editorReady ? "editor" : "idle"
        restoreWindow()
    }
    property bool editorReady: false
    function finishCapture(r, points) {
        const o = overlay
        overlay = null
        const rect = Qt.rect(Math.round(r.x), Math.round(r.y), Math.max(1, Math.round(r.width)), Math.max(1, Math.round(r.height)))
        const ok = editor.copyFrom(o.shot, rect, points)
        o.destroy()
        if (!ok) {
            cancelCapture()
            return
        }
        if (selectionInk) {
            // A thin outline around the snip, like the original's selection ink.
            if (points.length > 2) {
                editor.setPreview({ shape: "polygon", closed: true, outline: "solid", fill: "none", color: selectionInkColor, width: 2,
                                    points: points.map(p => Qt.point(p.x - rect.x, p.y - rect.y)) })
            } else {
                editor.setPreview({ shape: "rectangle", outline: "solid", fill: "none", color: selectionInkColor, width: 2,
                                    x1: 1, y1: 1, x2: rect.width - 1, y2: rect.height - 1 })
            }
            editor.commitPreview()
        }
        editor.modified = true
        editorReady = true
        savedPath = ""
        if (copyToClipboard)
            editor.copyImage()
        phase = "editor"
        inkTool = "pen"
        fitWindow(rect.width, rect.height)
        restoreWindow()
    }
    function restoreWindow() {
        if (!frame)
            return
        Shell.activate(frame)
        Qt.callLater(keepOnScreen)
        snip.forceActiveFocus()
    }
    function fitWindow(w, h) {
        if (!frame)
            return
        const a = Shell.workArea
        const chrome = menuBar.height + toolBar.height + 2 * 12
        const cw = Math.max(440, Math.min(a.width - 60, w + 2 * 12 + 4))
        const ch = Math.max(240, Math.min(a.height - 60, h + chrome + 4))
        if (frame.maximized)
            frame.restore()
        frame.internalWidth = cw
        frame.internalHeight = ch
        frame.x = a.x + (a.width - (cw + 2 * Theme.frameBorder)) / 2
        frame.y = a.y + Math.max(0, (a.height - (ch + Theme.titleHeight + Theme.frameBorder)) / 2)
        flick.contentX = 0
        flick.contentY = 0
    }
    function idleWindow() {
        phase = "idle"
        if (frame) {
            frame.internalWidth = 420
            frame.internalHeight = hideInstructions ? 34 : 96
        }
    }

    // ================================================================ save / copy
    function saveSnip(after) {
        const name = "Capture"
        fileDialog.afterSave = after || null
        fileDialog.types = [{ label: "Portable Network Graphic file (PNG) (*.PNG)", exts: ["png"] },
                            { label: "JPEG file (*.JPG)", exts: ["jpg", "jpeg"] },
                            { label: "Bitmap file (*.BMP)", exts: ["bmp"] }]
        let dir = savedPath.length ? Files.parentDir(savedPath) : Files.pictures + "/Screenshots"
        if (!Files.isDir(dir) && Files.isDir(Files.pictures))
            dir = Files.makeFolder(Files.pictures, "Screenshots") || Files.pictures
        fileDialog.show("save", dir, savedPath.length ? Files.fileName(savedPath) : name + ".png", 0)
    }
    function saveTo(p) {
        if (!editor.save(p)) {
            Shell.notify("The snip could not be saved", p, Theme.icon("snippingtool"))
            return false
        }
        savedPath = p
        return true
    }
    function copySnip() { if (hasSnip) editor.copyImage() }
    function confirmThen(action) {
        if (!unsaved || !promptToSave) {
            action()
            return
        }
        pendingAction = action
        savePrompt.open = true
    }
    function requestClose() {
        if (overlay)
            cancelCapture()
        if (closeConfirmed || !unsaved || !promptToSave)
            return true
        confirmThen(() => { snip.closeConfirmed = true; snip.frame.close() })
        return false
    }
    function showModeMenu(item) {
        const p = item.mapToItem(Shell.root, 0, item.height)
        Shell.showMenu(modes.map(m => ({ text: m[1], checked: snip.mode === m[0], action: () => snip.newSnip(m[0]) })), p.x, p.y)
    }
    function showPenMenu(item) {
        const p = item.mapToItem(Shell.root, 0, item.height)
        Shell.showMenu(pens.map(pn => ({ text: pn[0], checked: snip.inkTool === "pen" && Qt.colorEqual(snip.penColor, pn[1]),
                                         action: () => { snip.penColor = pn[1]; snip.inkTool = "pen" } })), p.x, p.y)
    }

    Keys.onPressed: (e) => {
        if (fileDialog.open || optionsDialog.open || aboutDialog.open || savePrompt.open)
            return
        if (e.modifiers & Qt.ControlModifier) {
            if (e.key === Qt.Key_N) { newSnip(); e.accepted = true }
            else if (e.key === Qt.Key_S && hasSnip) { saveSnip(); e.accepted = true }
            else if (e.key === Qt.Key_C && hasSnip) { copySnip(); e.accepted = true }
        }
    }

    // ================================================================ toolbar (both phases)
    component ToolButton: Item {
        id: tb
        property string label: ""
        property string icon: ""
        property bool arrow: false
        property bool split: false
        property bool checked: false
        signal clicked()
        signal arrowClicked()
        width: row.implicitWidth + (arrow ? 22 : 12)
        height: 24
        opacity: enabled ? 1 : 0.45
        Rectangle {
            anchors.fill: parent
            radius: 3
            visible: tb.enabled && (tbMa.containsMouse || tb.checked)
            border.color: tb.checked ? "#7da2ce" : "#a7c5e9"
            gradient: Gradient {
                GradientStop { position: 0; color: tb.checked || tbMa.pressed ? "#d6e7fb" : "#fbfdff" }
                GradientStop { position: 1; color: tb.checked || tbMa.pressed ? "#b5d0f1" : "#dfecfb" }
            }
            Rectangle { visible: tb.split; x: parent.width - 15; y: 3; width: 1; height: parent.height - 6; color: "#a7c5e9" }
        }
        Row {
            id: row
            x: 6
            height: parent.height
            spacing: 4
            AppIcon { visible: tb.icon.length > 0; size: 16; name: tb.icon.length ? Theme.icon(tb.icon) : ""; anchors.verticalCenter: parent.verticalCenter }
            VText { visible: tb.label.length > 0; text: tb.label; anchors.verticalCenter: parent.verticalCenter; color: "#1e395b" }
        }
        VText { visible: tb.arrow; anchors.right: parent.right; anchors.rightMargin: 4; anchors.verticalCenter: parent.verticalCenter; text: "▾"; font.pixelSize: 10; color: "#1e395b" }
        MouseArea {
            id: tbMa
            anchors.fill: parent
            hoverEnabled: true
            onClicked: (m) => {
                if (tb.arrow && (!tb.split || m.x > tb.width - 15)) tb.arrowClicked()
                else tb.clicked()
            }
        }
    }
    component Divider: Rectangle { width: 1; height: 20; color: "#c5d3e5"; anchors.verticalCenter: parent ? parent.verticalCenter : undefined }

    // ---- menu bar (editor only)
    Rectangle {
        id: menuBar
        visible: snip.hasSnip
        width: parent.width; height: visible ? 21 : 0
        gradient: Gradient {
            GradientStop { position: 0; color: "#ffffff" }
            GradientStop { position: 1; color: "#e9eef6" }
        }
        Row {
            x: 2; height: parent.height
            component MenuTitle: HoverItem {
                id: mt
                property string text: ""
                property var entries: []
                width: mtl.implicitWidth + 14; height: parent.height
                radius: 2
                VText { id: mtl; anchors.centerIn: parent; text: mt.text }
                onClicked: { const g = mapToItem(Shell.root, 0, height); Shell.showMenu(mt.entries, g.x, g.y) }
            }
            MenuTitle {
                text: "File"
                entries: [
                    { text: "New Snip\tCtrl+N", action: () => snip.newSnip() },
                    { text: "Save As...\tCtrl+S", action: () => snip.saveSnip() },
                    { separator: true },
                    { text: "Exit", action: () => snip.frame.close() }
                ]
            }
            MenuTitle { text: "Edit"; entries: [{ text: "Copy\tCtrl+C", action: () => snip.copySnip() }] }
            MenuTitle {
                text: "Tools"
                entries: [
                    { text: "Pen", action: () => snip.inkTool = "pen" },
                    { text: "Highlighter", checked: snip.inkTool === "highlighter", action: () => snip.inkTool = "highlighter" },
                    { text: "Eraser", checked: snip.inkTool === "eraser", action: () => snip.inkTool = "eraser" },
                    { separator: true },
                    { text: "Options...", action: () => optionsDialog.show() }
                ]
            }
            MenuTitle { text: "Help"; entries: [{ text: "About Snipping Tool", action: () => aboutDialog.open = true }] }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#d8dde6" }
    }

    Rectangle {
        id: toolBar
        y: menuBar.height
        width: parent.width; height: 32
        gradient: Gradient {
            GradientStop { position: 0; color: "#fafcfe" }
            GradientStop { position: 0.5; color: "#eef3fa" }
            GradientStop { position: 1; color: "#dde7f4" }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: "#b6c6da" }
        Row {
            x: 4
            height: parent.height
            spacing: 2
            ToolButton {
                id: newButton
                anchors.verticalCenter: parent.verticalCenter
                icon: "snip-new"; label: "New"; arrow: true; split: true
                onClicked: snip.newSnip()
                onArrowClicked: snip.showModeMenu(newButton)
            }
            ToolButton {
                visible: !snip.hasSnip
                anchors.verticalCenter: parent.verticalCenter
                label: "Cancel"
                enabled: snip.phase === "capturing"
                onClicked: snip.cancelCapture()
            }
            ToolButton {
                visible: !snip.hasSnip
                anchors.verticalCenter: parent.verticalCenter
                label: "Options"
                onClicked: optionsDialog.show()
            }
            // editor tools
            ToolButton { visible: snip.hasSnip; anchors.verticalCenter: parent.verticalCenter; icon: "paint-save"; label: "Save Snip"; onClicked: snip.saveSnip() }
            ToolButton { visible: snip.hasSnip; anchors.verticalCenter: parent.verticalCenter; icon: "paint-copy"; label: "Copy"; onClicked: snip.copySnip() }
            Divider { visible: snip.hasSnip }
            ToolButton {
                id: penButton
                visible: snip.hasSnip
                anchors.verticalCenter: parent.verticalCenter
                icon: "snip-pen"; arrow: true; split: true
                checked: snip.inkTool === "pen"
                onClicked: snip.inkTool = "pen"
                onArrowClicked: snip.showPenMenu(penButton)
                Rectangle { x: 6; y: 19; width: 16; height: 3; color: snip.penColor }
            }
            ToolButton { visible: snip.hasSnip; anchors.verticalCenter: parent.verticalCenter; icon: "snip-highlighter"; checked: snip.inkTool === "highlighter"; onClicked: snip.inkTool = "highlighter" }
            ToolButton { visible: snip.hasSnip; anchors.verticalCenter: parent.verticalCenter; icon: "paint-eraser"; checked: snip.inkTool === "eraser"; enabled: editor.hasInk; onClicked: snip.inkTool = "eraser" }
        }
    }

    // ---- idle: instruction text
    Rectangle {
        visible: !snip.hasSnip && !snip.hideInstructions
        y: toolBar.height
        width: parent.width
        height: parent.height - y
        color: "#ffffff"
        AppIcon { x: 14; y: 16; size: 32; name: Theme.icon("snippingtool") }
        VText {
            x: 58; y: 14
            width: parent.width - 72
            wrapMode: Text.Wrap
            maximumLineCount: 3
            color: "#1e395b"
            text: snip.phase === "capturing" ? "Drag the cursor around the area you want to capture."
                : "Drag the cursor around the area you want to capture. Click New, or press Ctrl+N, to start a "
                  + snip.modes.find(m => m[0] === snip.mode)[1].toLowerCase() + "."
        }
    }

    // ---- editor: the snip with ink
    Rectangle {
        id: editArea
        visible: snip.hasSnip
        y: toolBar.y + toolBar.height
        width: parent.width
        height: parent.height - y
        color: "#e6eaf0"
        Flickable {
            id: flick
            anchors.fill: parent
            clip: true
            interactive: false
            contentWidth: Math.max(width, editor.width + 24)
            contentHeight: Math.max(height, editor.height + 24)
            Rectangle { x: 13; y: 13; width: editor.width; height: editor.height; color: "#30000000" }
            PaintCanvas {
                id: editor
                x: 12; y: 12
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: snip.inkTool === "eraser" ? Qt.PointingHandCursor : Qt.CrossCursor
                    onPressed: (m) => snip.inkPress(m.x, m.y)
                    onPositionChanged: (m) => { if (pressed) snip.inkMove(m.x, m.y) }
                    onReleased: editor.inkEnd()
                    onWheel: (w) => {
                        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - w.angleDelta.y / 2))
                        flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - w.angleDelta.x / 2))
                    }
                }
            }
            ScrollIndicator7 { flickable: flick }
        }
    }
    function inkPress(x, y) {
        if (inkTool === "eraser")
            editor.inkEraseAt(Qt.point(x, y), 4)
        else if (inkTool === "highlighter")
            editor.inkBegin(Qt.point(x, y), "#fff200", 14, true)
        else
            editor.inkBegin(Qt.point(x, y), penColor, 3, false)
        editor.modified = true
    }
    function inkMove(x, y) {
        if (inkTool === "eraser")
            editor.inkEraseAt(Qt.point(x, y), 4)
        else
            editor.inkTo(Qt.point(x, y))
    }
    // Scriptable: draw an ink stroke through points.
    function inkStroke(points, tool) {
        if (tool)
            inkTool = tool
        inkPress(points[0][0], points[0][1])
        for (let i = 1; i < points.length; ++i)
            inkMove(points[i][0], points[i][1])
        editor.inkEnd()
    }
    readonly property alias editorCanvas: editor
    function closeAll() {
        for (const d of [fileDialog, optionsDialog, aboutDialog, savePrompt])
            d.open = false
        pendingAction = null
    }

    // ================================================================ overlay
    Component {
        id: overlayComponent
        FocusScope {
            id: ov
            property string mode: "rect"
            property alias shot: shot
            property point start: Qt.point(0, 0)
            property rect sel: Qt.rect(0, 0, 0, 0)
            property var points: []
            property bool dragging: false
            property var hoverWin: null
            readonly property rect hoverRect: hoverWin ? Qt.rect(Math.max(0, hoverWin.x), Math.max(0, hoverWin.y),
                                                                 Math.min(width, hoverWin.x + hoverWin.width) - Math.max(0, hoverWin.x),
                                                                 Math.min(height, hoverWin.y + hoverWin.height) - Math.max(0, hoverWin.y))
                                                      : Qt.rect(0, 0, width, height)
            readonly property rect clear: mode === "window" ? hoverRect : sel
            anchors.fill: parent
            z: 100000
            visible: false
            Keys.onEscapePressed: snip.cancelCapture()

            PaintCanvas { id: shot }
            // white wash everywhere except the area being captured
            Item {
                anchors.fill: parent
                visible: snip.showOverlay
                opacity: 0.62
                readonly property rect c: ov.mode === "free" ? Qt.rect(0, 0, 0, 0) : ov.clear
                Rectangle { x: 0; y: 0; width: parent.width; height: parent.c.y; color: "white" }
                Rectangle { x: 0; y: parent.c.y + parent.c.height; width: parent.width; height: parent.height - y; color: "white" }
                Rectangle { x: 0; y: parent.c.y; width: parent.c.x; height: parent.c.height; color: "white" }
                Rectangle { x: parent.c.x + parent.c.width; y: parent.c.y; width: parent.width - x; height: parent.c.height; color: "white" }
            }
            Rectangle { // red selection outline
                visible: ov.mode !== "free" && ov.clear.width > 0 && (ov.dragging || ov.mode === "window")
                x: ov.clear.x - 1; y: ov.clear.y - 1
                width: ov.clear.width + 2; height: ov.clear.height + 2
                color: "transparent"
                border.color: snip.selectionInkColor
                border.width: ov.mode === "window" ? 3 : 1
            }
            PaintMarquee {
                visible: ov.mode === "free" && ov.points.length > 1
                anchors.fill: parent
                dashed: false
                color: snip.selectionInkColor
                lineWidth: 2
                points: ov.points
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: ov.mode === "window" ? Qt.PointingHandCursor : Qt.CrossCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: (m) => ov.press(m.x, m.y, m.button)
                onPositionChanged: (m) => ov.move(m.x, m.y)
                onReleased: (m) => ov.release(m.x, m.y)
            }
            function windowAt(x, y) {
                const list = Shell.windows.filter(w => w !== snip.frame && !w.minimized && !w.closing && w.visible
                                                       && x >= w.x && y >= w.y && x < w.x + w.width && y < w.y + w.height)
                list.sort((a, b) => b.z - a.z)
                return list.length ? list[0] : null
            }
            function press(x, y, button) {
                if (button === Qt.RightButton) {
                    snip.cancelCapture()
                    return
                }
                if (mode === "window")
                    return
                dragging = true
                start = Qt.point(x, y)
                sel = Qt.rect(x, y, 0, 0)
                points = [Qt.point(x, y)]
            }
            function move(x, y) {
                if (mode === "window") {
                    hoverWin = windowAt(x, y)
                    return
                }
                if (!dragging)
                    return
                if (mode === "free")
                    points = points.concat([Qt.point(x, y)])
                else
                    sel = Qt.rect(Math.min(start.x, x), Math.min(start.y, y), Math.abs(x - start.x), Math.abs(y - start.y))
            }
            function release(x, y) {
                if (mode === "window") {
                    hoverWin = windowAt(x, y)
                    snip.finishCapture(Qt.rect(hoverRect.x, hoverRect.y, hoverRect.width, hoverRect.height), [])
                    return
                }
                if (!dragging)
                    return
                dragging = false
                if (mode === "free") {
                    if (points.length < 3) return
                    let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
                    for (const p of points) { x0 = Math.min(x0, p.x); y0 = Math.min(y0, p.y); x1 = Math.max(x1, p.x); y1 = Math.max(y1, p.y) }
                    if (x1 - x0 < 2 || y1 - y0 < 2) return
                    snip.finishCapture(Qt.rect(Math.floor(x0), Math.floor(y0), Math.ceil(x1 - x0) + 1, Math.ceil(y1 - y0) + 1), points)
                } else {
                    if (sel.width < 2 || sel.height < 2) return
                    snip.finishCapture(Qt.rect(sel.x, sel.y, sel.width, sel.height), [])
                }
            }
            // Scriptable drag for the demo.
            function dragThrough(pts) {
                press(pts[0][0], pts[0][1], Qt.LeftButton)
                for (let i = 1; i < pts.length; ++i)
                    move(pts[i][0], pts[i][1])
                const l = pts[pts.length - 1]
                release(l[0], l[1])
            }
        }
    }

    // ================================================================ dialogs
    PaintFileDialog {
        id: fileDialog
        tracking: snip.frame
        property var afterSave: null
        onAccepted: (p, t) => {
            if (snip.saveTo(p)) {
                const a = afterSave
                afterSave = null
                if (a) a()
            }
        }
    }
    PaintDialog {
        id: optionsDialog
        title: "Snipping Tool Options"
        tracking: snip.frame
        clientWidth: 360
        clientHeight: 270
        function show() {
            o1.checked = snip.hideInstructions
            o2.checked = snip.copyToClipboard
            o3.checked = snip.promptToSave
            o4.checked = snip.showOverlay
            o5.checked = snip.selectionInk
            inkCombo.currentIndex = Math.max(0, snip.pens.findIndex(p => Qt.colorEqual(p[1], snip.selectionInkColor)))
            open = true
        }
        function close() { open = false }
        onRejected: close()
        Column {
            x: 16; y: 12
            spacing: 3
            VText { text: "Application"; color: "#1e395b"; font.bold: true }
            CheckBox7 { id: o1; text: "Hide Instruction Text" }
            CheckBox7 { id: o2; text: "Always copy snips to the Clipboard" }
            CheckBox7 { id: o3; text: "Prompt to save snips before exiting" }
            CheckBox7 { id: o4; text: "Show screen overlay when Snipping Tool is active" }
            Item { width: 1; height: 8 }
            VText { text: "Selections"; color: "#1e395b"; font.bold: true }
            Row {
                spacing: 8
                VText { text: "Ink color:"; anchors.verticalCenter: parent.verticalCenter }
                PaintCombo { id: inkCombo; width: 120; model: snip.pens.map(p => p[0].replace(" Pen", "")) }
            }
            CheckBox7 { id: o5; text: "Show selection ink after snips are captured" }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            y: 236
            spacing: 8
            Button7 {
                text: "OK"; isDefault: true
                onClicked: {
                    snip.hideInstructions = o1.checked
                    snip.copyToClipboard = o2.checked
                    snip.promptToSave = o3.checked
                    snip.showOverlay = o4.checked
                    snip.selectionInk = o5.checked
                    snip.selectionInkColor = snip.pens[inkCombo.currentIndex][1]
                    optionsDialog.close()
                }
            }
            Button7 { text: "Cancel"; onClicked: optionsDialog.close() }
        }
    }
    PaintDialog {
        id: aboutDialog
        title: "About Snipping Tool"
        tracking: snip.frame
        clientWidth: 340
        clientHeight: 150
        onRejected: open = false
        AppIcon { x: 16; y: 16; size: 48; name: Theme.icon("snippingtool") }
        VText { x: 78; y: 18; text: "Snipping Tool"; font.pixelSize: 18; color: "#1e395b" }
        VText { x: 78; y: 44; width: parent.width - 90; wrapMode: Text.Wrap; text: "Capture all or part of your screen, then add notes and save or share it.\nVitrum " + Session.version }
        Button7 { anchors.right: parent.right; anchors.rightMargin: 12; y: 116; text: "OK"; isDefault: true; onClicked: aboutDialog.open = false }
    }
    PaintDialog {
        id: savePrompt
        title: "Snipping Tool"
        tracking: snip.frame
        clientWidth: 380
        clientHeight: 120
        onRejected: { open = false; snip.pendingAction = null }
        Rectangle { width: parent.width; height: 76; color: "white" }
        VText { x: 18; y: 22; width: parent.width - 36; text: "Do you want to save changes to the Snipping Tool?"; color: "#003399"; font.pixelSize: 15; wrapMode: Text.Wrap }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            y: 87
            spacing: 8
            Button7 {
                text: "Yes"; isDefault: true
                onClicked: { savePrompt.open = false; const a = snip.pendingAction; snip.pendingAction = null; snip.saveSnip(a) }
            }
            Button7 {
                text: "No"
                onClicked: { savePrompt.open = false; const a = snip.pendingAction; snip.pendingAction = null; editor.modified = false; if (a) a() }
            }
            Button7 { text: "Cancel"; onClicked: { savePrompt.open = false; snip.pendingAction = null } }
        }
    }
}
