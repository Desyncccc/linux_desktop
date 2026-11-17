import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// Paint: a raster editor with a scenic ribbon (Paint menu, Home, View and a
// contextual Text tab), a zoomable canvas with resize handles and a status
// bar. Drawing happens in PaintCanvas (C++); this file wires up the tools.
FocusScope {
    id: app
    property var frame: null
    property string path: ""
    readonly property string docName: path.length ? Files.fileName(path) : "Untitled"
    readonly property alias paintCanvas: canvas

    // ---- tool state
    property string tool: "pencil"       // select pencil fill text eraser picker magnifier brush shape
    property string prevTool: "pencil"
    property string selectMode: "rect"   // rect | free
    property string brushStyle: "brush"
    property string shape: "rectangle"
    property string outlineStyle: "solid"
    property string fillStyle: "none"
    property color color1: "#000000"
    property color color2: "#ffffff"
    property int activeColor: 1
    property var customColors: ["", "", "", "", "", "", "", "", "", ""]
    property string tab: "home"
    property bool showRulers: false
    property bool showStatus: true
    property var recent: []
    property bool closeConfirmed: false
    property var pendingAction: null
    property string popup: ""            // "" | "appmenu" | "brushes" | "size"
    property point popupPos: Qt.point(0, 0)
    property string appMenuPane: "recent"

    readonly property var sizeTables: ({
        pencil: [1, 2, 3, 4], brush: [2, 4, 8, 12], airbrush: [6, 10, 16, 24], eraser: [4, 6, 8, 10], shape: [1, 3, 5, 8]
    })
    property var sizeChoice: ({ pencil: 0, brush: 1, airbrush: 1, eraser: 1, shape: 0 })
    readonly property string sizeKind: tool === "pencil" ? "pencil" : tool === "eraser" ? "eraser"
                                     : tool === "brush" ? (brushStyle === "airbrush" ? "airbrush" : "brush")
                                     : tool === "shape" ? "shape" : ""
    // Ribbon groups collapse into drop-down buttons, right to left, as the window narrows.
    readonly property real ribbonWidth: width
    readonly property int homeLevel: ribbonWidth >= 1052 ? 0 : ribbonWidth >= 766 ? 1 : ribbonWidth >= 566 ? 2
                                   : ribbonWidth >= 492 ? 3 : ribbonWidth >= 430 ? 4 : 5
    property Item poppedGroup: null
    readonly property int currentSize: sizeKind.length ? sizeTables[sizeKind][sizeChoice[sizeKind]] : 1

    readonly property var palette: [
        "#000000", "#7f7f7f", "#880015", "#ed1c24", "#ff7f27", "#fff200", "#22b14c", "#00a2e8", "#3f48cc", "#a349a4",
        "#ffffff", "#c3c3c3", "#b97a57", "#ffaec9", "#ffc90e", "#efe4b0", "#b5e61d", "#99d9ea", "#7092be", "#c8bfe7"
    ]
    readonly property var shapes: [
        ["line", "Line"], ["curve", "Curve"], ["oval", "Oval"], ["rectangle", "Rectangle"], ["roundrect", "Rounded rectangle"],
        ["polygon", "Polygon"], ["triangle", "Triangle"], ["righttriangle", "Right triangle"], ["diamond", "Diamond"],
        ["pentagon", "Pentagon"], ["hexagon", "Hexagon"], ["arrowright", "Right arrow"], ["arrowleft", "Left arrow"],
        ["arrowup", "Up arrow"], ["arrowdown", "Down arrow"], ["star4", "Four-point star"], ["star5", "Five-point star"],
        ["star6", "Six-point star"], ["calloutrect", "Rounded rectangular callout"], ["calloutoval", "Oval callout"],
        ["cloud", "Cloud callout"], ["heart", "Heart"], ["lightning", "Lightning"]
    ]
    readonly property var brushes: [
        ["brush", "Brush"], ["calligraphy1", "Calligraphy brush 1"], ["calligraphy2", "Calligraphy brush 2"],
        ["airbrush", "Airbrush"], ["oil", "Oil brush"], ["crayon", "Crayon"], ["marker", "Marker"],
        ["pencil2", "Natural pencil"], ["watercolor", "Watercolor brush"]
    ]
    readonly property var styleNames: [["solid", "Solid color"], ["crayon", "Crayon"], ["marker", "Marker"],
                                       ["oil", "Oil"], ["pencil", "Natural pencil"], ["watercolor", "Watercolor"]]
    readonly property var zoomSteps: [0.125, 0.25, 0.5, 1, 2, 3, 4, 5, 6, 7, 8]
    readonly property var saveTypes: [
        { label: "PNG (*.png)", exts: ["png"] },
        { label: "JPEG (*.jpg;*.jpeg;*.jpe;*.jfif)", exts: ["jpg", "jpeg", "jpe", "jfif"] },
        { label: "24-bit Bitmap (*.bmp;*.dib)", exts: ["bmp", "dib"] },
        { label: "TIFF (*.tif;*.tiff)", exts: ["tif", "tiff"] }
    ]
    readonly property var openTypes: [
        { label: "All Picture Files", exts: ["png", "jpg", "jpeg", "jpe", "jfif", "bmp", "dib", "gif", "tif", "tiff", "ico", "webp"] },
        { label: "All Files (*.*)", exts: ["*"] }
    ]

    // ---- text tool state
    property bool textActive: false
    property rect textRect: Qt.rect(0, 0, 0, 0)
    property string textFamily: Theme.font
    property int textPoints: 11
    property bool textBold: false
    property bool textItalic: false
    property bool textUnderline: false
    property bool textStrike: false
    property bool textOpaque: false
    readonly property int textPixels: Math.round(textPoints * 4 / 3)

    // ---- pointer state (image coordinates)
    property bool dragging: false
    property int dragButton: Qt.LeftButton
    property point dragStart: Qt.point(0, 0)
    property point hoverPos: Qt.point(-1, -1)
    property bool selecting: false
    property bool movingSel: false
    property point moveOffset: Qt.point(0, 0)
    property var lasso: []
    property rect rubber: Qt.rect(0, 0, 0, 0)
    property int curveStage: 0
    property var curvePts: []
    property bool polyActive: false
    property var polyPts: []
    property int shapeButton: Qt.LeftButton

    property string loadedPath: ""     // the file the canvas holds (path may be set from outside)
    onPathChanged: if (path.length && path !== loadedPath) loadFile(path)
    onDocNameChanged: updateTitle()
    Component.onCompleted: { updateTitle(); forceActiveFocus() }
    Component.onDestruction: exitFullScreen()
    function updateTitle() { if (frame) frame.internalTitle = docName + " - Paint" }
    onFrameChanged: {
        updateTitle()
        if (frame) {
            frame.internalMinWidth = 420
            frame.internalMinHeight = 300
            Qt.callLater(keepOnScreen)
        }
    }
    // The frame is placed before its width is known; pull it back on screen.
    function keepOnScreen() {
        const a = Shell.workArea
        if (frame && frame.x + frame.width > a.x + a.width)
            frame.x = Math.max(a.x, a.x + (a.width - frame.width) / 2)
    }

    // ================================================================ document
    function loadFile(p) {
        if (!canvas.load(p)) {
            Shell.notify("Paint cannot read this file", Files.fileName(p), Theme.icon("paint"))
            return false
        }
        loadedPath = p
        if (path !== p)
            path = p
        addRecent(p)
        zoomTo(1)
        return true
    }
    function addRecent(p) {
        recent = [p].concat(recent.filter(x => x !== p)).slice(0, 9)
    }
    function save(after) {
        commitPending()
        if (!path.length) {
            saveAs(0, after)
            return false
        }
        if (!canvas.save(path)) {
            Shell.notify("Paint could not save the picture", path, Theme.icon("paint"))
            return false
        }
        addRecent(path)
        if (after)
            after()
        return true
    }
    function typeIndexFor(p) {
        const dot = p.lastIndexOf(".")
        const ext = dot > 0 ? p.substring(dot + 1).toLowerCase() : ""
        for (let i = 0; i < saveTypes.length; ++i)
            if (saveTypes[i].exts.indexOf(ext) >= 0)
                return i
        return 0
    }
    function saveAs(typeIndex, after) {
        commitPending()
        popup = ""
        const base = path.length ? Files.fileName(path).replace(/\.[^.]*$/, "") : "Untitled"
        const t = typeIndex === undefined ? (path.length ? typeIndexFor(path) : 0) : typeIndex
        fileDialog.afterSave = after || null
        fileDialog.types = saveTypes
        fileDialog.show("save", path.length ? Files.parentDir(path) : Files.pictures, base + "." + saveTypes[t].exts[0], t)
    }
    function openFile() {
        popup = ""
        confirmThen(() => {
            fileDialog.afterSave = null
            fileDialog.types = openTypes
            fileDialog.show("open", path.length ? Files.parentDir(path) : Files.pictures, "", 0)
        })
    }
    function newImage() {
        popup = ""
        confirmThen(() => {
            cancelPending()
            canvas.newImage(800, 600)
            loadedPath = ""
            path = ""
            zoomTo(1)
            flick.contentX = 0
            flick.contentY = 0
        })
    }
    // Run `action` once unsaved changes are dealt with.
    function confirmThen(action) {
        if (!canvas.modified) {
            action()
            return
        }
        pendingAction = action
        savePrompt.open = true
    }
    function requestClose() {
        if (closeConfirmed || !canvas.modified)
            return true
        confirmThen(() => { app.closeConfirmed = true; app.frame.close() })
        return false
    }
    function exit() { popup = ""; if (frame) frame.close() }
    // Show a collapsed group's controls in a drop-down by borrowing them.
    function openGroup(g, button) {
        const was = poppedGroup
        popup = ""
        if (was === g)
            return
        const c = g.contentItem
        if (!c)
            return
        c.parent = groupHost
        c.x = 0
        c.y = 0
        g.popped = true
        poppedGroup = g
        popupPos = button.mapToItem(app, 0, button.height + 2)
        popup = "group"
    }
    function returnGroup() {
        const g = poppedGroup
        if (!g)
            return
        poppedGroup = null
        g.popped = false
        g.contentItem.parent = g.holderItem
        g.contentItem.x = 0
        g.contentItem.y = 0
    }
    onPopupChanged: if (popup !== "group") returnGroup()
    onRibbonWidthChanged: if (popup === "group") popup = ""
    onToolChanged: if (popup === "group") popup = ""
    onShapeChanged: if (popup === "group") popup = ""
    function togglePopup(name, anchor) {
        if (popup === name) {
            popup = ""
            return
        }
        popupPos = anchor.mapToItem(app, 0, anchor.height + 2)
        popup = name
    }

    // ================================================================ editing
    function undo() { cancelPending(); canvas.undo() }
    function redo() { cancelPending(); canvas.redo() }
    function cut() { if (textActive) { textEdit.cut(); return } canvas.cutSelection() }
    function copy() { if (textActive) { textEdit.copy(); return } canvas.copySelection() }
    function paste() {
        if (textActive) { textEdit.paste(); return }
        const vx = Math.max(0, Math.floor((flick.contentX - page.x) / canvas.zoom))
        const vy = Math.max(0, Math.floor((flick.contentY - page.y) / canvas.zoom))
        if (canvas.paste(vx, vy))
            setTool("select")
    }
    function pasteFrom() {
        fileDialog.afterSave = null
        fileDialog.types = openTypes
        fileDialog.pasteMode = true
        fileDialog.show("open", Files.pictures, "", 0)
    }
    function selectAll() { setTool("select"); canvas.selectAll() }
    function deleteSelection() { canvas.deleteSelection() }
    function crop() { commitPending(); if (canvas.hasSelection) canvas.cropToSelection() }

    function setTool(t) {
        if (t === tool)
            return
        commitPending()
        if (t !== "select")
            canvas.clearSelection()
        if (t === "picker" || t === "magnifier")
            prevTool = tool === "picker" || tool === "magnifier" ? prevTool : tool
        tool = t
    }
    // Finish anything half-done: text box, curve, polygon.
    function commitPending() {
        if (textActive)
            commitText()
        if (curveStage > 0 || polyActive) {
            if (polyActive)
                previewPolygon(true)
            canvas.commitPreview()
            curveStage = 0
            polyActive = false
            polyPts = []
        }
    }
    function cancelPending() {
        textActive = false
        textEdit.text = ""
        curveStage = 0
        polyActive = false
        polyPts = []
        canvas.clearPreview()
        lasso = []
        selecting = false
    }

    // ================================================================ zoom
    function zoomTo(z, ax, ay) {
        z = Math.max(0.125, Math.min(8, z))
        if (ax === undefined) { ax = flick.width / 2; ay = flick.height / 2 }
        const old = canvas.zoom
        const ix = (flick.contentX + ax - page.x) / old
        const iy = (flick.contentY + ay - page.y) / old
        canvas.zoom = z
        const cw = canvas.imageWidth * z + page.x + 40, ch = canvas.imageHeight * z + page.y + 40
        flick.contentX = Math.max(0, Math.min(cw - flick.width, ix * z + page.x - ax))
        flick.contentY = Math.max(0, Math.min(ch - flick.height, iy * z + page.y - ay))
    }
    function zoomStep(dir, ax, ay) {
        const z = canvas.zoom
        let next = z
        if (dir > 0) { for (let i = 0; i < zoomSteps.length; ++i) if (zoomSteps[i] > z + 0.001) { next = zoomSteps[i]; break } }
        else { for (let i = zoomSteps.length - 1; i >= 0; --i) if (zoomSteps[i] < z - 0.001) { next = zoomSteps[i]; break } }
        zoomTo(next, ax, ay)
    }

    // ================================================================ pointer → tools
    function constrain(p, mods) {
        if (!(mods & Qt.ShiftModifier))
            return p
        const dx = p.x - dragStart.x, dy = p.y - dragStart.y
        if (tool === "shape" && (shape === "line" || shape === "curve")) {
            const a = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * (Math.PI / 4)
            const len = Math.sqrt(dx * dx + dy * dy)
            return Qt.point(dragStart.x + Math.round(Math.cos(a) * len), dragStart.y + Math.round(Math.sin(a) * len))
        }
        const s = Math.max(Math.abs(dx), Math.abs(dy))
        return Qt.point(dragStart.x + (dx < 0 ? -s : s), dragStart.y + (dy < 0 ? -s : s))
    }
    function shapeSpec(extra) {
        const left = shapeButton === Qt.LeftButton
        const spec = {
            shape: shape, outline: outlineStyle, fill: fillStyle,
            color: left ? color1 : color2, fillColor: left ? color2 : color1, width: currentSize
        }
        for (const k in extra)
            spec[k] = extra[k]
        return spec
    }
    function previewPolygon(closed) {
        canvas.setPreview(shapeSpec({ points: polyPts, closed: closed }))
    }
    function inSelection(x, y) {
        const s = canvas.selection
        return canvas.hasSelection && x >= s.x && y >= s.y && x < s.x + s.width && y < s.y + s.height
    }

    function press(x, y, button, mods) {
        const primary = button !== Qt.RightButton
        const c = primary ? color1 : color2
        const p = Qt.point(x, y)
        popup = ""
        if (!textActive)
            takeKeys()
        dragButton = button
        dragStart = p
        dragging = true
        switch (tool) {
        case "pencil":
            canvas.beginStroke("pencil", c, "transparent", currentSize, p)
            break
        case "brush":
            canvas.beginStroke(brushStyle, c, "transparent", currentSize, p)
            if (brushStyle === "airbrush")
                sprayTimer.start()
            break
        case "eraser":
            canvas.beginStroke("eraser", color2, primary ? "transparent" : color1, currentSize, p)
            break
        case "fill":
            canvas.floodFill(Math.floor(x), Math.floor(y), c)
            dragging = false
            break
        case "picker": {
            const k = canvas.pixelAt(Math.floor(x), Math.floor(y))
            if (primary) color1 = k
            else color2 = k
            tool = prevTool
            dragging = false
            break
        }
        case "magnifier": {
            const vp = page.mapToItem(flick, x * canvas.zoom, y * canvas.zoom)
            zoomStep(primary ? 1 : -1, vp.x, vp.y)
            dragging = false
            break
        }
        case "text":
            if (textActive) {
                commitText()
                dragging = false
            }
            break
        case "select":
            if (inSelection(x, y)) {
                if (!primary) {
                    dragging = false
                    showCanvasMenu(x, y)
                    return
                }
                movingSel = true
                moveOffset = Qt.point(x - canvas.selection.x, y - canvas.selection.y)
                if ((mods & Qt.ControlModifier) && !canvas.floating) {
                    // Ctrl+drag leaves the original in place.
                    canvas.copySelection()
                    const s = Qt.point(canvas.selection.x, canvas.selection.y)
                    canvas.clearSelection()
                    canvas.paste(s.x, s.y)
                }
            } else {
                canvas.clearSelection()
                selecting = true
                lasso = [p]
                rubber = Qt.rect(x, y, 0, 0)
            }
            break
        case "shape":
            if (shape === "curve" && curveStage > 0) {
                bendCurve(p)
            } else if (shape === "polygon" && polyActive) {
                const first = polyPts[0]
                if (Math.abs(first.x - x) * canvas.zoom < 5 && Math.abs(first.y - y) * canvas.zoom < 5) {
                    finishPolygon()
                    dragging = false
                } else {
                    polyPts = polyPts.concat([p])
                    previewPolygon(false)
                }
            } else {
                shapeButton = button
                curveStage = 0
            }
            break
        }
    }
    function move(x, y, mods) {
        hoverPos = Qt.point(x, y)
        if (!dragging)
            return
        const p = Qt.point(x, y)
        switch (tool) {
        case "pencil": case "brush": case "eraser":
            canvas.strokeTo(p)
            break
        case "select":
            if (movingSel) {
                canvas.moveSelectionTo(Math.round(x - moveOffset.x), Math.round(y - moveOffset.y))
            } else if (selecting) {
                if (selectMode === "free") {
                    const cx = Math.max(0, Math.min(canvas.imageWidth, x)), cy = Math.max(0, Math.min(canvas.imageHeight, y))
                    lasso = lasso.concat([Qt.point(cx, cy)])
                } else {
                    const cx = Math.max(0, Math.min(canvas.imageWidth, Math.round(x)))
                    const cy = Math.max(0, Math.min(canvas.imageHeight, Math.round(y)))
                    const sx = Math.round(dragStart.x), sy = Math.round(dragStart.y)
                    rubber = Qt.rect(Math.min(sx, cx), Math.min(sy, cy), Math.abs(cx - sx), Math.abs(cy - sy))
                }
            }
            break
        case "text": {
            rubber = Qt.rect(Math.min(dragStart.x, x), Math.min(dragStart.y, y), Math.abs(x - dragStart.x), Math.abs(y - dragStart.y))
            break
        }
        case "shape": {
            const q = constrain(p, mods)
            if (shape === "curve" && curveStage > 0) {
                bendCurve(p)
            } else if (shape === "polygon" && polyActive) {
                const pts = polyPts.slice()
                pts[pts.length - 1] = q
                polyPts = pts
                previewPolygon(false)
            } else if (shape === "curve") {
                canvas.setPreview(shapeSpec({ points: [dragStart, q, dragStart, q] }))
            } else if (shape === "polygon") {
                canvas.setPreview(shapeSpec({ points: [dragStart, q], closed: false }))
            } else {
                canvas.setPreview(shapeSpec({ x1: Math.round(dragStart.x), y1: Math.round(dragStart.y), x2: Math.round(q.x), y2: Math.round(q.y) }))
            }
            break
        }
        }
    }
    function release(x, y, mods) {
        if (!dragging)
            return
        dragging = false
        const p = Qt.point(x, y)
        switch (tool) {
        case "pencil": case "brush": case "eraser":
            sprayTimer.stop()
            canvas.endStroke()
            break
        case "select":
            if (movingSel) {
                movingSel = false
            } else if (selecting) {
                selecting = false
                if (selectMode === "free" && lasso.length > 2)
                    canvas.setFreeFormSelection(lasso)
                else if (selectMode === "rect" && rubber.width >= 1 && rubber.height >= 1)
                    canvas.setSelection(rubber)
                lasso = []
                rubber = Qt.rect(0, 0, 0, 0)
            }
            break
        case "text": {
            const r = rubber.width > 8 && rubber.height > 8 ? Qt.rect(rubber.x, rubber.y, rubber.width, rubber.height)
                    : Qt.rect(Math.round(x), Math.round(y), Math.max(40, Math.min(240, canvas.imageWidth - Math.round(x))), textPixels * 1.6)
            rubber = Qt.rect(0, 0, 0, 0)
            startText(r)
            break
        }
        case "shape": {
            const q = constrain(p, mods)
            if (shape === "curve") {
                if (curveStage === 0) {
                    if (Math.abs(q.x - dragStart.x) + Math.abs(q.y - dragStart.y) < 2) { canvas.clearPreview(); break }
                    const a = Qt.point(dragStart.x, dragStart.y)
                    curvePts = [a, q, a, q]
                    curveStage = 1
                    canvas.setPreview(shapeSpec({ points: curvePts }))
                } else if (curveStage === 1) {
                    curveStage = 2
                } else {
                    canvas.commitPreview()
                    curveStage = 0
                }
            } else if (shape === "polygon") {
                if (!polyActive) {
                    if (Math.abs(q.x - dragStart.x) + Math.abs(q.y - dragStart.y) < 2) { canvas.clearPreview(); break }
                    polyPts = [Qt.point(dragStart.x, dragStart.y), q]
                    polyActive = true
                    previewPolygon(false)
                }
            } else if (Math.abs(q.x - dragStart.x) >= 1 || Math.abs(q.y - dragStart.y) >= 1) {
                canvas.setPreview(shapeSpec({ x1: Math.round(dragStart.x), y1: Math.round(dragStart.y), x2: Math.round(q.x), y2: Math.round(q.y) }))
                canvas.commitPreview()
            } else {
                canvas.clearPreview()
            }
            break
        }
        }
    }
    function doubleClick(x, y) {
        if (tool === "shape" && shape === "polygon" && polyActive)
            finishPolygon()
    }
    function bendCurve(p) {
        const pts = curvePts.slice()
        if (curveStage === 1) { pts[2] = p; pts[3] = p }
        else pts[3] = p
        curvePts = pts
        canvas.setPreview(shapeSpec({ points: pts }))
    }
    function finishPolygon() {
        if (polyPts.length > 2) {
            previewPolygon(true)
            canvas.commitPreview()
        } else {
            canvas.clearPreview()
        }
        polyActive = false
        polyPts = []
    }

    // Scriptable helpers (also used by the demo): drag a tool over points.
    function drag(points, button) {
        const b = button || Qt.LeftButton
        press(points[0][0], points[0][1], b, 0)
        for (let i = 1; i < points.length; ++i)
            move(points[i][0], points[i][1], 0)
        const last = points[points.length - 1]
        release(last[0], last[1], 0)
    }
    function click(x, y, button) { drag([[x, y]], button) }
    function typeText(t) { textEdit.insert(textEdit.length, t) }
    function showResize() { resizeDialog.show() }
    function closeDialogs() {
        for (const d of [fileDialog, colorDialog, resizeDialog, propertiesDialog, aboutDialog, savePrompt])
            d.open = false
        pendingAction = null
        popup = ""
    }

    // ---- text tool
    function startText(r) {
        textRect = Qt.rect(Math.round(r.x), Math.round(r.y), Math.max(20, Math.round(r.width)), Math.max(textPixels + 6, Math.round(r.height)))
        textEdit.text = ""
        textActive = true
        tab = "text"
        textEdit.forceActiveFocus()
    }
    function commitText() {
        if (!textActive)
            return
        const t = textEdit.text
        textActive = false
        if (tab === "text")
            tab = "home"
        if (t.length > 0) {
            const h = Math.max(textRect.height, textEdit.contentHeight / canvas.zoom + 2)
            canvas.drawText(Qt.rect(textRect.x, textRect.y, textRect.width, h), t,
                            { family: textFamily, pixelSize: textPixels, bold: textBold, italic: textItalic,
                              underline: textUnderline, strikeout: textStrike, padding: 1 },
                            color1, textOpaque, color2)
        }
        textEdit.text = ""
        takeKeys()
    }
    // A FocusScope hands focus back to its last focused child, so drop the
    // text box's claim first.
    function takeKeys() {
        textEdit.focus = false
        app.forceActiveFocus()
    }

    // ---- colours
    function pickColor(c, button) {
        if (button === Qt.RightButton || activeColor === 2)
            color2 = c
        else
            color1 = c
    }
    function editColors() {
        colorDialog.show(activeColor === 1 ? color1 : color2)
    }

    function showCanvasMenu(x, y) {
        const g = page.mapToItem(Shell.root, x * canvas.zoom, y * canvas.zoom)
        Shell.showMenu([
            { text: "Cut\tCtrl+X", icon: Theme.icon("paint-cut"), enabled: canvas.hasSelection, action: () => app.cut() },
            { text: "Copy\tCtrl+C", icon: Theme.icon("paint-copy"), enabled: canvas.hasSelection, action: () => app.copy() },
            { text: "Paste\tCtrl+V", icon: Theme.icon("paint-paste"), enabled: canvas.clipboardHasImage, action: () => app.paste() },
            { separator: true },
            { text: "Crop", icon: Theme.icon("paint-crop"), enabled: canvas.hasSelection, action: () => app.crop() },
            { text: "Select all\tCtrl+A", icon: Theme.icon("paint-selectall"), action: () => app.selectAll() },
            { text: "Delete\tDel", icon: Theme.icon("paint-delete"), enabled: canvas.hasSelection, action: () => app.deleteSelection() },
            { separator: true },
            { text: "Rotate right 90°", icon: Theme.icon("paint-rotright"), action: () => canvas.rotate(90) },
            { text: "Rotate left 90°", icon: Theme.icon("paint-rotleft"), action: () => canvas.rotate(-90) },
            { text: "Flip vertical", icon: Theme.icon("paint-flipv"), action: () => canvas.flip(false) },
            { text: "Flip horizontal", icon: Theme.icon("paint-fliph"), action: () => canvas.flip(true) },
            { text: "Resize\tCtrl+W", icon: Theme.icon("paint-resize"), action: () => resizeDialog.show() },
            { text: "Invert color\tCtrl+Shift+I", icon: Theme.icon("paint-invert"), action: () => canvas.invertColors() }
        ], g.x, g.y)
    }

    property var fullScreenView: null
    function fullScreen() {
        commitPending()
        fullScreenView = fullScreenComponent.createObject(Shell.root, { source: canvas })
    }
    function exitFullScreen() {
        if (fullScreenView)
            fullScreenView.destroy()
        fullScreenView = null
    }

    // ================================================================ keyboard
    readonly property bool modal: fileDialog.open || colorDialog.open || resizeDialog.open || propertiesDialog.open
                                  || aboutDialog.open || savePrompt.open
    Keys.onPressed: (e) => {
        if (modal)
            return
        const ctrl = e.modifiers & Qt.ControlModifier
        const shift = e.modifiers & Qt.ShiftModifier
        if (ctrl) {
            switch (e.key) {
            case Qt.Key_Z: undo(); break
            case Qt.Key_Y: redo(); break
            case Qt.Key_S: if (shift) saveAs(); else save(); break
            case Qt.Key_O: openFile(); break
            case Qt.Key_N: newImage(); break
            case Qt.Key_A: selectAll(); break
            case Qt.Key_C: copy(); break
            case Qt.Key_X: cut(); break
            case Qt.Key_V: paste(); break
            case Qt.Key_E: propertiesDialog.show(); break
            case Qt.Key_W: resizeDialog.show(); break
            case Qt.Key_R: showRulers = !showRulers; break
            case Qt.Key_G: canvas.showGrid = !canvas.showGrid; break
            case Qt.Key_I:
                if (shift) canvas.invertColors()
                else if (textActive) textItalic = !textItalic
                else { e.accepted = false; return }
                break
            case Qt.Key_B: if (textActive) textBold = !textBold; else { e.accepted = false; return } break
            case Qt.Key_U: if (textActive) textUnderline = !textUnderline; else { e.accepted = false; return } break
            case Qt.Key_PageUp: zoomStep(1); break
            case Qt.Key_PageDown: zoomStep(-1); break
            case Qt.Key_Plus: case Qt.Key_Equal: bumpSize(1); break
            case Qt.Key_Minus: bumpSize(-1); break
            default: e.accepted = false; return
            }
            e.accepted = true
            return
        }
        switch (e.key) {
        case Qt.Key_Delete: deleteSelection(); break
        case Qt.Key_Escape:
            if (popup.length) popup = ""
            else if (dragging || curveStage > 0 || polyActive) { dragging = false; cancelPending(); canvas.endStroke() }
            else canvas.clearSelection()
            break
        case Qt.Key_F11: fullScreen(); break
        case Qt.Key_F12: saveAs(); break
        default: e.accepted = false; return
        }
        e.accepted = true
    }
    function bumpSize(d) {
        if (!sizeKind.length)
            return
        const c = Object.assign({}, sizeChoice)
        c[sizeKind] = Math.max(0, Math.min(3, c[sizeKind] + d))
        sizeChoice = c
    }

    Timer { id: sprayTimer; interval: 40; repeat: true; onTriggered: canvas.spray() }

    component ColorButton: PaintRibbonButton {
        id: cbtn
        property int which: 1
        large: true
        width: 40
        checked: app.activeColor === which
        text: "Color\n" + which
        tip: which === 1 ? "Color 1 (foreground color)\nClick here and then select a color from the palette.\nThis color is used with the pencil and with brushes, as well as for shape outlines."
                         : "Color 2 (background color)\nClick here and then select a color from the palette.\nThis color is used with the eraser and for shape fills."
        onClicked: app.activeColor = which
        Rectangle {
            x: (cbtn.width - width) / 2; y: 4
            width: 30; height: 30
            color: "white"
            border.color: "#8ea4c1"
            Rectangle {
                anchors.fill: parent
                anchors.margins: 3
                color: cbtn.which === 1 ? app.color1 : app.color2
                border.color: Qt.rgba(0, 0, 0, 0.25)
            }
        }
    }

    // ================================================================ ribbon tabs
    Rectangle {
        id: tabRow
        width: parent.width; height: 25
        gradient: Gradient {
            GradientStop { position: 0; color: "#e4edf8" }
            GradientStop { position: 1; color: "#d9e5f4" }
        }
        // Paint menu button
        Item {
            id: appButton
            x: 3; y: 2
            width: 54; height: 23
            Rectangle {
                anchors.fill: parent
                anchors.bottomMargin: -1
                radius: 3
                border.color: "#1c4882"
                gradient: Gradient {
                    GradientStop { position: 0; color: appMa.containsMouse || app.popup === "appmenu" ? "#5b9ee8" : "#4a8adb" }
                    GradientStop { position: 0.48; color: appMa.containsMouse || app.popup === "appmenu" ? "#3477cf" : "#2d68bd" }
                    GradientStop { position: 0.52; color: appMa.containsMouse || app.popup === "appmenu" ? "#1f5fb9" : "#1a51a3" }
                    GradientStop { position: 1; color: appMa.containsMouse || app.popup === "appmenu" ? "#3b86dc" : "#2a68bf" }
                }
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 2
                    color: "transparent"
                    border.color: Qt.rgba(1, 1, 1, 0.35)
                }
            }
            Row {
                anchors.centerIn: parent
                spacing: 4
                AppIcon { size: 16; name: Theme.icon("paint-menu"); anchors.verticalCenter: parent.verticalCenter }
                Text { text: "▾"; color: "white"; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
            }
            MouseArea {
                id: appMa
                anchors.fill: parent
                hoverEnabled: true
                onClicked: { app.commitPending(); app.appMenuPane = "recent"; app.popup = app.popup === "appmenu" ? "" : "appmenu" }
            }
        }
        Row {
            id: tabs
            x: appButton.x + appButton.width + 4
            y: 3
            height: parent.height - 3
            spacing: 1
            component Tab: Item {
                id: tb
                property string key: ""
                property string label: ""
                property bool contextual: false
                readonly property bool current: app.tab === key
                width: tl.implicitWidth + 24
                height: parent.height
                visible: !contextual || app.textActive
                Rectangle {
                    anchors.fill: parent
                    anchors.bottomMargin: -1
                    radius: 3
                    visible: tb.current || tbMa.containsMouse
                    border.color: tb.current ? "#b6c9e2" : "#cbdaec"
                    gradient: Gradient {
                        GradientStop { position: 0; color: tb.current ? "#ffffff" : "#f2f7fd" }
                        GradientStop { position: 1; color: tb.current ? "#f6f9fd" : "#e4edf8" }
                    }
                }
                Rectangle {
                    visible: tb.contextual
                    width: parent.width; height: 3
                    radius: 1
                    color: "#f4c84b"
                }
                VText {
                    id: tl
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 1
                    text: tb.label
                    color: "#1e395b"
                }
                MouseArea { id: tbMa; anchors.fill: parent; hoverEnabled: true; onClicked: app.tab = tb.key }
            }
            Tab { key: "home"; label: "Home" }
            Tab { key: "view"; label: "View" }
            Tab { key: "text"; label: "Text"; contextual: true }
        }
        // quick commands on the right
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 6
            y: 2
            spacing: 1
            PaintRibbonButton { iconName: "paint-save"; tip: "Save (Ctrl+S)"; onClicked: app.save() }
            PaintRibbonButton { iconName: "paint-undo"; tip: "Undo (Ctrl+Z)"; enabled: canvas.canUndo || app.textActive; onClicked: app.undo() }
            PaintRibbonButton { iconName: "paint-redo"; tip: "Redo (Ctrl+Y)"; enabled: canvas.canRedo; onClicked: app.redo() }
            PaintRibbonButton { iconName: "paint-about"; tip: "Paint Help"; onClicked: aboutDialog.open = true }
        }
    }

    // ================================================================ ribbon panel
    Rectangle {
        id: ribbon
        y: tabRow.height
        width: parent.width; height: 94
        border.color: "#b6c9e2"
        gradient: Gradient {
            GradientStop { position: 0; color: "#fdfeff" }
            GradientStop { position: 0.75; color: "#edf3fb" }
            GradientStop { position: 1; color: "#dfe9f5" }
        }
        Rectangle { // bottom edge
            anchors.bottom: parent.bottom
            width: parent.width; height: 1
            color: "#9fb6d4"
        }
        clip: true

        // ---- shared groups
        component ClipboardGroup: PaintRibbonGroup {
            title: "Clipboard"
            icon: "paint-paste"
            onExpandRequested: (g, b) => app.openGroup(g, b)
            Row {
                spacing: 2
                PaintRibbonButton {
                    large: true; split: true; arrow: true
                    iconName: "paint-paste"; text: "Paste"
                    tip: "Paste (Ctrl+V)"
                    enabled: canvas.clipboardHasImage || app.textActive
                    onClicked: app.paste()
                    onArrowClicked: { const p = menuPos(); Shell.showMenu([
                        { text: "Paste\tCtrl+V", icon: Theme.icon("paint-paste"), enabled: canvas.clipboardHasImage, action: () => app.paste() },
                        { text: "Paste from...", icon: Theme.icon("paint-open"), action: () => app.pasteFrom() }
                    ], p.x, p.y) }
                }
                Column {
                    y: 2
                    spacing: 1
                    PaintRibbonButton { iconName: "paint-cut"; text: "Cut"; tip: "Cut (Ctrl+X)"; enabled: canvas.hasSelection || app.textActive; onClicked: app.cut() }
                    PaintRibbonButton { iconName: "paint-copy"; text: "Copy"; tip: "Copy (Ctrl+C)"; enabled: canvas.hasSelection || app.textActive; onClicked: app.copy() }
                }
            }
        }
        component ColorsGroup: PaintRibbonGroup {
            title: "Colors"
            icon: "paint-editcolors"
            onExpandRequested: (g, b) => app.openGroup(g, b)
            divider: false
            Row {
                spacing: 2
                ColorButton { which: 1 }
                ColorButton { which: 2 }
                Grid {
                    y: 3
                    columns: 10
                    rowSpacing: 2; columnSpacing: 1
                    Repeater {
                        model: app.palette.concat(app.customColors)
                        Rectangle {
                            id: sw
                            required property string modelData
                            required property int index
                            readonly property bool empty: modelData === ""
                            width: 18; height: 18
                            color: swMa.containsMouse && !empty ? "#e8f2fd" : "transparent"
                            border.color: swMa.containsMouse && !empty ? "#5a92d6" : "transparent"
                            Rectangle {
                                anchors.centerIn: parent
                                width: 14; height: 14
                                color: sw.empty ? "white" : sw.modelData
                                border.color: sw.empty ? "#c5d3e5" : "#a0a0a0"
                            }
                            MouseArea {
                                id: swMa
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                enabled: !sw.empty
                                onClicked: (m) => app.pickColor(sw.modelData, m.button)
                            }
                        }
                    }
                }
                PaintRibbonButton {
                    large: true
                    iconName: "paint-editcolors"
                    text: "Edit\ncolors"
                    tip: "Edit colors\nSelect a color from the color palette."
                    onClicked: app.editColors()
                }
            }
        }

        // ---- Home
        Row {
            id: homeRow
            visible: app.tab === "home"
            height: parent.height - 2
            ClipboardGroup { collapsed: app.homeLevel >= 4 }
            PaintRibbonGroup {
                title: "Image"
                icon: "paint-select"
                collapsed: app.homeLevel >= 3
                onExpandRequested: (g, b) => app.openGroup(g, b)
                Row {
                    spacing: 2
                    PaintRibbonButton {
                        large: true; split: true; arrow: true
                        iconName: "paint-select"; text: "Select"
                        checked: app.tool === "select"
                        tip: "Select\nSelect a part of the picture."
                        onClicked: app.setTool("select")
                        onArrowClicked: { const p = menuPos(); Shell.showMenu([
                            { text: "Rectangular selection", icon: Theme.icon("paint-rectselect"), checked: app.selectMode === "rect", action: () => { app.selectMode = "rect"; app.setTool("select") } },
                            { text: "Free-form selection", icon: Theme.icon("paint-freeform"), checked: app.selectMode === "free", action: () => { app.selectMode = "free"; app.setTool("select") } },
                            { separator: true },
                            { text: "Select all\tCtrl+A", icon: Theme.icon("paint-selectall"), action: () => app.selectAll() },
                            { text: "Delete\tDel", icon: Theme.icon("paint-delete"), enabled: canvas.hasSelection, action: () => app.deleteSelection() },
                            { text: "Transparent selection", icon: Theme.icon("paint-transparent"), checked: canvas.transparentSelection, action: () => { canvas.transparentSelection = !canvas.transparentSelection } }
                        ], p.x, p.y) }
                    }
                    Column {
                        y: 0
                        spacing: 0
                        PaintRibbonButton { iconName: "paint-crop"; text: "Crop"; tip: "Crop (Ctrl+Shift+X)\nCrop the picture so it only contains the current selection."; enabled: canvas.hasSelection; onClicked: app.crop() }
                        PaintRibbonButton { iconName: "paint-resize"; text: "Resize"; tip: "Resize and skew (Ctrl+W)"; onClicked: resizeDialog.show() }
                        PaintRibbonButton {
                            iconName: "paint-rotate"; text: "Rotate"; arrow: true
                            tip: "Rotate or flip"
                            onArrowClicked: { const p = menuPos(); Shell.showMenu([
                                { text: "Rotate right 90°", icon: Theme.icon("paint-rotright"), action: () => canvas.rotate(90) },
                                { text: "Rotate left 90°", icon: Theme.icon("paint-rotleft"), action: () => canvas.rotate(-90) },
                                { text: "Rotate 180°", icon: Theme.icon("paint-rot180"), action: () => canvas.rotate(180) },
                                { text: "Flip vertical", icon: Theme.icon("paint-flipv"), action: () => canvas.flip(false) },
                                { text: "Flip horizontal", icon: Theme.icon("paint-fliph"), action: () => canvas.flip(true) }
                            ], p.x, p.y) }
                        }
                    }
                }
            }
            PaintRibbonGroup {
                title: "Tools"
                icon: "paint-pencil"
                collapsed: app.homeLevel >= 5
                onExpandRequested: (g, b) => app.openGroup(g, b)
                Grid {
                    y: 5
                    columns: 3
                    spacing: 2
                    component ToolButton: PaintRibbonButton {
                        property string toolName: ""
                        width: 24; height: 24
                        checked: app.tool === toolName
                        onClicked: app.setTool(toolName)
                    }
                    ToolButton { toolName: "pencil"; iconName: "paint-pencil"; tip: "Pencil\nDraw a free-form line with the selected line width." }
                    ToolButton { toolName: "fill"; iconName: "paint-fill"; tip: "Fill with color\nClick an area on the canvas to fill it with the foreground color, or right-click to fill it with the background color." }
                    ToolButton { toolName: "text"; iconName: "paint-text"; tip: "Text\nInsert text into the picture." }
                    ToolButton { toolName: "eraser"; iconName: "paint-eraser"; tip: "Eraser\nErase part of the picture and replace it with the background color." }
                    ToolButton { toolName: "picker"; iconName: "paint-picker"; tip: "Color picker\nPick a color from the picture and use it for drawing." }
                    ToolButton { toolName: "magnifier"; iconName: "paint-magnifier"; tip: "Magnifier\nChange the magnification for a part of the picture." }
                }
            }
            PaintRibbonGroup {
                title: "Brushes"
                PaintRibbonButton {
                    id: brushesButton
                    large: true; split: true; arrow: true
                    width: 50
                    text: "Brushes"
                    tip: "Brushes\nDraw with different brushes."
                    checked: app.tool === "brush"
                    onClicked: app.setTool("brush")
                    onArrowClicked: app.togglePopup("brushes", brushesButton)
                    PaintGlyph {
                        x: (brushesButton.width - width) / 2; y: 3
                        width: 34; height: 32
                        brush: app.brushStyle
                        color: "#1e395b"
                    }
                }
            }
            PaintRibbonGroup {
                title: "Shapes"
                icon: "paint-shapes"
                collapsed: app.homeLevel >= 2
                onExpandRequested: (g, b) => app.openGroup(g, b)
                Row {
                    spacing: 4
                    Rectangle {
                        id: gallery
                        property int row: 0
                        readonly property int rows: Math.ceil(app.shapes.length / 7)
                        width: 7 * 21 + 3 + 14; height: 66
                        color: "white"
                        border.color: "#b6c9e2"
                        clip: true
                        Grid {
                            x: 2; y: 2 - gallery.row * 21
                            columns: 7
                            Repeater {
                                model: app.shapes
                                Item {
                                    id: gi
                                    required property var modelData
                                    width: 21; height: 21
                                    readonly property bool on: app.tool === "shape" && app.shape === modelData[0]
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        radius: 2
                                        visible: gi.on || giMa.containsMouse
                                        color: gi.on ? "#c4dcf7" : "#e8f2fd"
                                        border.color: gi.on ? "#6d98cc" : "#a7c5e9"
                                    }
                                    PaintGlyph { anchors.centerIn: parent; width: 15; height: 15; shape: gi.modelData[0] }
                                    MouseArea {
                                        id: giMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: { app.setTool("shape"); app.commitPending(); app.shape = gi.modelData[0] }
                                        onContainsMouseChanged: {
                                            if (containsMouse) { const p = gi.mapToItem(Shell.root, 0, gi.height); Shell.showTooltip(gi.modelData[1], p.x, p.y) }
                                            else Shell.hideTooltip()
                                        }
                                    }
                                }
                            }
                        }
                        Column { // scroll buttons
                            anchors.right: parent.right
                            anchors.rightMargin: 1
                            y: 1
                            Repeater {
                                model: ["▴", "▾", "≡"]
                                Rectangle {
                                    required property string modelData
                                    required property int index
                                    width: 14; height: 21.3
                                    color: scMa.containsMouse ? "#e8f2fd" : "#f3f7fc"
                                    border.color: "#c5d6ea"
                                    Text { anchors.centerIn: parent; text: parent.modelData; font.pixelSize: 9; color: "#1e395b" }
                                    MouseArea {
                                        id: scMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            if (parent.index === 0) gallery.row = Math.max(0, gallery.row - 1)
                                            else if (parent.index === 1) gallery.row = Math.min(gallery.rows - 3, gallery.row + 1)
                                            else gallery.row = (gallery.row + 1) % (gallery.rows - 2)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Column {
                        y: 4
                        spacing: 2
                        PaintRibbonButton {
                            iconName: "paint-outline"; text: "Outline"; arrow: true
                            enabled: app.tool === "shape"
                            tip: "Shape outline\nSelect the medium for the shape outline."
                            onArrowClicked: {
                                const p = menuPos()
                                const items = [{ text: "No outline", checked: app.outlineStyle === "none", action: () => app.outlineStyle = "none" }]
                                for (const s of app.styleNames) { const k = s[0]; items.push({ text: s[1], checked: app.outlineStyle === k, action: () => app.outlineStyle = k }) }
                                Shell.showMenu(items, p.x, p.y)
                            }
                        }
                        PaintRibbonButton {
                            iconName: "paint-shapefill"; text: "Fill"; arrow: true
                            enabled: app.tool === "shape"
                            tip: "Shape fill\nSelect the medium for the shape fill. The fill uses Color 2."
                            onArrowClicked: {
                                const p = menuPos()
                                const items = [{ text: "No fill", checked: app.fillStyle === "none", action: () => app.fillStyle = "none" }]
                                for (const s of app.styleNames) { const k = s[0]; items.push({ text: s[1], checked: app.fillStyle === k, action: () => app.fillStyle = k }) }
                                Shell.showMenu(items, p.x, p.y)
                            }
                        }
                    }
                }
            }
            PaintRibbonGroup {
                title: "Size"
                PaintRibbonButton {
                    id: sizeButton
                    large: true; arrow: true
                    iconName: "paint-size"
                    width: 40
                    enabled: app.sizeKind.length > 0
                    tip: "Size (Ctrl++, Ctrl+-)\nSelect the width for the selected tool."
                    onArrowClicked: app.togglePopup("size", sizeButton)
                }
            }
            ColorsGroup { collapsed: app.homeLevel >= 1 }
        }

        // ---- View
        Row {
            visible: app.tab === "view"
            height: parent.height - 2
            PaintRibbonGroup {
                title: "Zoom"
                Row {
                    spacing: 2
                    PaintRibbonButton { large: true; iconName: "paint-zoomin"; text: "Zoom\nin"; tip: "Zoom in (Ctrl+PgUp)"; enabled: canvas.zoom < 8; onClicked: app.zoomStep(1) }
                    PaintRibbonButton { large: true; iconName: "paint-zoomout"; text: "Zoom\nout"; tip: "Zoom out (Ctrl+PgDn)"; enabled: canvas.zoom > 0.125; onClicked: app.zoomStep(-1) }
                    PaintRibbonButton { large: true; iconName: "paint-zoom100"; text: "100\n%"; tip: "100%\nView the picture at 100%."; onClicked: app.zoomTo(1) }
                }
            }
            PaintRibbonGroup {
                title: "Show or hide"
                Column {
                    y: 4
                    spacing: 1
                    CheckBox7 { text: "Rulers"; checked: app.showRulers; onToggled: (c) => app.showRulers = c }
                    CheckBox7 { text: "Gridlines"; checked: canvas.showGrid; onToggled: (c) => canvas.showGrid = c }
                    CheckBox7 { text: "Status bar"; checked: app.showStatus; onToggled: (c) => app.showStatus = c }
                }
            }
            PaintRibbonGroup {
                title: "Display"
                PaintRibbonButton { large: true; iconName: "paint-fullscreen"; text: "Full\nscreen"; tip: "Full screen (F11)"; onClicked: app.fullScreen() }
            }
        }

        // ---- Text (contextual)
        Row {
            visible: app.tab === "text"
            height: parent.height - 2
            ClipboardGroup {}
            PaintRibbonGroup {
                title: "Font"
                Column {
                    y: 4
                    spacing: 4
                    Row {
                        spacing: 4
                        PaintCombo {
                            id: familyCombo
                            width: 140
                            readonly property var families: {
                                const want = [Theme.font, "Sans Serif", "DejaVu Sans", "DejaVu Serif", "DejaVu Sans Mono", "Liberation Sans",
                                              "Liberation Serif", "Liberation Mono", "Noto Sans", "Noto Serif", "Noto Sans Mono", "Ubuntu", "Cantarell"]
                                const have = Qt.fontFamilies()
                                const out = []
                                for (const f of want)
                                    if (out.indexOf(f) < 0 && (f === Theme.font || have.indexOf(f) >= 0))
                                        out.push(f)
                                return out
                            }
                            model: families
                            currentIndex: Math.max(0, families.indexOf(app.textFamily))
                            onActivated: (i) => { app.textFamily = families[i]; textEdit.forceActiveFocus() }
                        }
                        PaintCombo {
                            width: 52
                            readonly property var sizes: [8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 26, 28, 36, 48, 72]
                            model: sizes.map(s => String(s))
                            currentIndex: Math.max(0, sizes.indexOf(app.textPoints))
                            onActivated: (i) => { app.textPoints = sizes[i]; textEdit.forceActiveFocus() }
                        }
                    }
                    Row {
                        spacing: 2
                        component StyleToggle: PaintRibbonButton {
                            property string glyph: ""
                            width: 24; height: 22
                            VText { anchors.centerIn: parent; text: parent.glyph; color: "#1e395b"; font.family: "serif"; font.pixelSize: 14 }
                        }
                        StyleToggle { glyph: "B"; checked: app.textBold; tip: "Bold (Ctrl+B)"; onClicked: { app.textBold = !app.textBold; textEdit.forceActiveFocus() } }
                        StyleToggle { glyph: "I"; checked: app.textItalic; tip: "Italic (Ctrl+I)"; onClicked: { app.textItalic = !app.textItalic; textEdit.forceActiveFocus() } }
                        StyleToggle { glyph: "U"; checked: app.textUnderline; tip: "Underline (Ctrl+U)"; onClicked: { app.textUnderline = !app.textUnderline; textEdit.forceActiveFocus() } }
                        StyleToggle { glyph: "S"; checked: app.textStrike; tip: "Strikethrough"; onClicked: { app.textStrike = !app.textStrike; textEdit.forceActiveFocus() } }
                    }
                }
            }
            PaintRibbonGroup {
                title: "Background"
                Column {
                    y: 4
                    spacing: 1
                    PaintRibbonButton { text: "Opaque"; checked: app.textOpaque; tip: "Opaque\nThe text background is filled with Color 2."; onClicked: { app.textOpaque = true; textEdit.forceActiveFocus() } }
                    PaintRibbonButton { text: "Transparent"; checked: !app.textOpaque; tip: "Transparent\nThe picture shows through behind the text."; onClicked: { app.textOpaque = false; textEdit.forceActiveFocus() } }
                }
            }
            ColorsGroup { collapsed: app.ribbonWidth < 840 }
        }
    }

    // ================================================================ canvas area
    Rectangle {
        id: area
        y: ribbon.y + ribbon.height
        width: parent.width
        height: parent.height - y - (app.showStatus ? status.height : 0)
        color: "#cad7e8"
        clip: true
        readonly property real pageW: page.x + page.width + 30
        readonly property real pageH: page.y + page.height + 30
        readonly property real availW: width - vRuler.width
        readonly property real availH: height - hRuler.height
        readonly property bool needH: pageW > availW || (pageH > availH && pageW > availW - 17)
        readonly property bool needV: pageH > availH || (pageW > availW && pageH > availH - 17)

        MouseArea { // clicking the background finishes the current edit
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressed: { app.popup = ""; app.commitPending(); app.takeKeys() }
            onWheel: (w) => area.wheelScroll(w)
        }
        function wheelScroll(w) {
            if (w.modifiers & Qt.ControlModifier) {
                const p = mapToItem(flick, w.x, w.y)
                app.zoomStep(w.angleDelta.y > 0 ? 1 : -1, p.x, p.y)
                return
            }
            const dx = (w.modifiers & Qt.ShiftModifier) ? -w.angleDelta.y : -w.angleDelta.x
            const dy = (w.modifiers & Qt.ShiftModifier) ? 0 : -w.angleDelta.y
            flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX + dx / 2))
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy / 2))
        }

        // ---- rulers
        Canvas {
            id: hRuler
            visible: app.showRulers
            x: vRuler.width; y: 0
            width: parent.width - x; height: app.showRulers ? 18 : 0
            onPaint: app.paintRuler(getContext("2d"), width, height, flick.contentX - page.x, true)
        }
        Canvas {
            id: vRuler
            visible: app.showRulers
            x: 0; y: hRuler.height
            width: app.showRulers ? 18 : 0; height: parent.height - y
            onPaint: app.paintRuler(getContext("2d"), height, width, flick.contentY - page.y, false)
        }
        Rectangle { visible: app.showRulers; width: vRuler.width; height: hRuler.height; color: "#f4f7fb"; border.color: "#b8c7da" }
        Connections {
            target: flick
            function onContentXChanged() { if (app.showRulers) hRuler.requestPaint() }
            function onContentYChanged() { if (app.showRulers) vRuler.requestPaint() }
        }
        Connections {
            target: canvas
            function onZoomChanged() { hRuler.requestPaint(); vRuler.requestPaint() }
        }
        Connections {
            target: app
            function onShowRulersChanged() { hRuler.requestPaint(); vRuler.requestPaint() }
            function onHoverPosChanged() { if (app.showRulers) { hRuler.requestPaint(); vRuler.requestPaint() } }
        }

        Flickable {
            id: flick
            x: vRuler.width; y: hRuler.height
            width: area.availW - (area.needV ? 17 : 0)
            height: area.availH - (area.needH ? 17 : 0)
            contentWidth: Math.max(width, area.pageW)
            contentHeight: Math.max(height, area.pageH)
            interactive: false
            clip: true

            Item {
                id: page
                x: 5; y: 5
                width: canvasBox.width + 8
                height: canvasBox.height + 8

                // drop shadow
                Rectangle { x: 3; y: 3; width: canvasBox.width + 1; height: canvasBox.height + 1; color: "#26000000" }
                Rectangle { x: 2; y: 2; width: canvasBox.width + 1; height: canvasBox.height + 1; color: "#30000000" }
                Rectangle { x: 1; y: 1; width: canvasBox.width; height: canvasBox.height; color: "#48000000" }

                Item { // the whole picture at the current zoom; the canvas below only renders what is visible
                    id: canvasBox
                    width: canvas.imageWidth * canvas.zoom
                    height: canvas.imageHeight * canvas.zoom
                }
                PaintCanvas {
                    id: canvas
                    secondaryColor: app.color2
                    readonly property real vx0: Math.max(0, flick.contentX - page.x)
                    readonly property real vy0: Math.max(0, flick.contentY - page.y)
                    x: Math.min(vx0, Math.max(0, canvasBox.width - 1))
                    y: Math.min(vy0, Math.max(0, canvasBox.height - 1))
                    width: Math.max(1, Math.min(canvasBox.width, flick.contentX - page.x + flick.width) - x)
                    height: Math.max(1, Math.min(canvasBox.height, flick.contentY - page.y + flick.height) - y)
                    origin: Qt.point(x, y)
                }

                MouseArea {
                    id: toolArea
                    anchors.fill: canvasBox
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    preventStealing: true
                    cursorShape: app.tool === "text" ? Qt.IBeamCursor
                               : app.tool === "eraser" ? Qt.BlankCursor
                               : app.tool === "fill" || app.tool === "picker" ? Qt.PointingHandCursor
                               : app.tool === "select" && app.inSelection(app.hoverPos.x, app.hoverPos.y) ? Qt.SizeAllCursor
                               : Qt.CrossCursor
                    onPressed: (m) => app.press(m.x / canvas.zoom, m.y / canvas.zoom, m.button, m.modifiers)
                    onPositionChanged: (m) => app.move(m.x / canvas.zoom, m.y / canvas.zoom, m.modifiers)
                    onReleased: (m) => app.release(m.x / canvas.zoom, m.y / canvas.zoom, m.modifiers)
                    onDoubleClicked: (m) => app.doubleClick(m.x / canvas.zoom, m.y / canvas.zoom)
                    onExited: app.hoverPos = Qt.point(-1, -1)
                    onWheel: (w) => area.wheelScroll(w)
                }

                // eraser footprint
                Rectangle {
                    visible: app.tool === "eraser" && app.hoverPos.x >= 0
                    x: (Math.floor(app.hoverPos.x) - Math.floor(app.currentSize / 2)) * canvas.zoom
                    y: (Math.floor(app.hoverPos.y) - Math.floor(app.currentSize / 2)) * canvas.zoom
                    width: app.currentSize * canvas.zoom; height: width
                    color: app.color2
                    border.color: "black"
                }

                // rubber band / lasso while selecting, text box outline while dragging
                PaintMarquee {
                    visible: app.rubber.width > 0 && app.rubber.height > 0 && (app.selecting || app.tool === "text")
                    x: app.rubber.x * canvas.zoom; y: app.rubber.y * canvas.zoom
                    width: Math.max(1, app.rubber.width * canvas.zoom + 1); height: Math.max(1, app.rubber.height * canvas.zoom + 1)
                }
                PaintMarquee {
                    visible: app.selecting && app.selectMode === "free"
                    width: canvasBox.width; height: canvasBox.height
                    points: app.lasso.map(p => Qt.point(p.x * canvas.zoom, p.y * canvas.zoom))
                }

                // selection
                Item {
                    id: selBox
                    visible: canvas.hasSelection
                    x: canvas.selection.x * canvas.zoom
                    y: canvas.selection.y * canvas.zoom
                    width: canvas.selection.width * canvas.zoom
                    height: canvas.selection.height * canvas.zoom
                    PaintMarquee { x: -1; y: -1; width: parent.width + 2; height: parent.height + 2 }
                    Repeater {
                        model: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1]]
                        Rectangle {
                            id: sh
                            required property var modelData
                            x: modelData[0] * selBox.width - 3
                            y: modelData[1] * selBox.height - 3
                            width: 5; height: 5
                            color: "white"
                            border.color: "#3c4a5c"
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -3
                                preventStealing: true
                                cursorShape: sh.modelData[0] === 0.5 ? Qt.SizeVerCursor : sh.modelData[1] === 0.5 ? Qt.SizeHorCursor
                                           : (sh.modelData[0] === sh.modelData[1]) ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                                property rect start
                                property point origin
                                onPressed: (m) => {
                                    start = canvas.selection
                                    origin = mapToItem(page, m.x, m.y)
                                }
                                onPositionChanged: (m) => {
                                    if (!pressed) return
                                    const g = mapToItem(page, m.x, m.y)
                                    const dx = (g.x - origin.x) / canvas.zoom, dy = (g.y - origin.y) / canvas.zoom
                                    let x = start.x, y = start.y, w = start.width, h = start.height
                                    if (sh.modelData[0] === 0) { x += dx; w -= dx } else if (sh.modelData[0] === 1) w += dx
                                    if (sh.modelData[1] === 0) { y += dy; h -= dy } else if (sh.modelData[1] === 1) h += dy
                                    selGhost.r = Qt.rect(Math.round(x), Math.round(y), Math.max(1, Math.round(w)), Math.max(1, Math.round(h)))
                                }
                                onReleased: {
                                    const r = Qt.rect(selGhost.r.x, selGhost.r.y, selGhost.r.width, selGhost.r.height)
                                    selGhost.r = Qt.rect(0, 0, 0, 0)
                                    if (r.width < 1)
                                        return
                                    canvas.resizeImage(r.width, r.height)
                                    canvas.moveSelectionTo(r.x, r.y)
                                }
                            }
                        }
                    }
                }
                PaintMarquee {
                    id: selGhost
                    property rect r: Qt.rect(0, 0, 0, 0)
                    visible: r.width > 0
                    x: r.x * canvas.zoom; y: r.y * canvas.zoom
                    width: r.width * canvas.zoom + 1; height: r.height * canvas.zoom + 1
                }

                // text box
                Item {
                    id: textBox
                    visible: app.textActive
                    x: app.textRect.x * canvas.zoom
                    y: app.textRect.y * canvas.zoom
                    width: app.textRect.width * canvas.zoom
                    height: Math.max(app.textRect.height * canvas.zoom, textEdit.contentHeight + 2 * canvas.zoom)
                    Rectangle { anchors.fill: parent; visible: app.textOpaque; color: app.color2 }
                    TextEdit {
                        id: textEdit
                        x: canvas.zoom; y: canvas.zoom
                        width: parent.width - 2 * canvas.zoom
                        wrapMode: TextEdit.Wrap
                        color: app.color1
                        font.family: app.textFamily
                        font.pixelSize: Math.max(1, app.textPixels * canvas.zoom)
                        font.bold: app.textBold
                        font.italic: app.textItalic
                        font.underline: app.textUnderline
                        font.strikeout: app.textStrike
                        selectByMouse: true
                        selectionColor: "#3399ff"
                        Keys.onEscapePressed: app.commitText()
                    }
                    PaintMarquee { x: -2; y: -2; width: parent.width + 4; height: parent.height + 4 }
                    MouseArea { // drag the box by its border
                        x: -5; y: -5; width: parent.width + 10; height: 5
                        cursorShape: Qt.SizeAllCursor
                        property point origin
                        onPressed: (m) => origin = Qt.point(m.x, m.y)
                        onPositionChanged: (m) => { if (pressed) app.textRect = Qt.rect(app.textRect.x + Math.round((m.x - origin.x) / canvas.zoom), app.textRect.y + Math.round((m.y - origin.y) / canvas.zoom), app.textRect.width, app.textRect.height) }
                    }
                    Rectangle { // width grip
                        x: parent.width + 1; y: parent.height + 1
                        width: 5; height: 5
                        color: "white"; border.color: "#3c4a5c"
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -3
                            cursorShape: Qt.SizeFDiagCursor
                            onPositionChanged: (m) => {
                                if (!pressed) return
                                const g = mapToItem(page, m.x, m.y)
                                app.textRect = Qt.rect(app.textRect.x, app.textRect.y,
                                                       Math.max(20, Math.round(g.x / canvas.zoom - app.textRect.x)),
                                                       Math.max(app.textPixels + 6, Math.round(g.y / canvas.zoom - app.textRect.y)))
                            }
                        }
                    }
                }

                // canvas resize handles (right, bottom, corner)
                Repeater {
                    model: [[1, 0.5], [0.5, 1], [1, 1]]
                    Rectangle {
                        id: ch
                        required property var modelData
                        x: modelData[0] * canvasBox.width + (modelData[0] === 1 ? 1 : -2)
                        y: modelData[1] * canvasBox.height + (modelData[1] === 1 ? 1 : -2)
                        width: 5; height: 5
                        color: "white"
                        border.color: "#55667a"
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -3
                            hoverEnabled: true
                            preventStealing: true
                            cursorShape: ch.modelData[0] === 1 && ch.modelData[1] === 1 ? Qt.SizeFDiagCursor
                                       : ch.modelData[0] === 1 ? Qt.SizeHorCursor : Qt.SizeVerCursor
                            onPressed: { app.commitPending(); resizeGhost.size = Qt.size(canvas.imageWidth, canvas.imageHeight) }
                            onPositionChanged: (m) => {
                                if (!pressed) return
                                const g = mapToItem(page, m.x, m.y)
                                resizeGhost.size = Qt.size(ch.modelData[0] === 1 ? Math.max(1, Math.round(g.x / canvas.zoom)) : canvas.imageWidth,
                                                           ch.modelData[1] === 1 ? Math.max(1, Math.round(g.y / canvas.zoom)) : canvas.imageHeight)
                            }
                            onReleased: {
                                const s = Qt.size(resizeGhost.size.width, resizeGhost.size.height)
                                resizeGhost.size = Qt.size(0, 0)
                                canvas.resizeCanvas(s.width, s.height)
                            }
                        }
                    }
                }
                PaintMarquee {
                    id: resizeGhost
                    property size size: Qt.size(0, 0)
                    visible: size.width > 0
                    width: size.width * canvas.zoom + 1
                    height: size.height * canvas.zoom + 1
                }
            }
        }

        // ---- scroll bars
        component Bar: Rectangle {
            id: bar
            property bool vertical: false
            property real position: 0      // content offset
            property real pageSize: 1
            property real total: 1
            signal scrolled(real pos)
            color: "#eceff3"
            border.color: "#dfe3e8"
            readonly property real track: (vertical ? height : width) - 34
            Rectangle {
                id: thumb
                readonly property real len: Math.max(18, bar.track * Math.min(1, bar.pageSize / Math.max(1, bar.total)))
                readonly property real off: 17 + (bar.track - len) * (bar.position / Math.max(1, bar.total - bar.pageSize))
                x: bar.vertical ? 2 : off
                y: bar.vertical ? off : 2
                width: bar.vertical ? bar.width - 4 : len
                height: bar.vertical ? len : bar.height - 4
                radius: 2
                border.color: thMa.containsMouse || thMa.pressed ? "#3c7fb1" : "#9a9a9a"
                gradient: Gradient {
                    orientation: bar.vertical ? Gradient.Horizontal : Gradient.Vertical
                    GradientStop { position: 0; color: thMa.containsMouse ? "#eaf6fd" : "#f3f3f3" }
                    GradientStop { position: 1; color: thMa.containsMouse ? "#b3dcf4" : "#dadada" }
                }
                MouseArea {
                    id: thMa
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true
                    property real grab: 0
                    property real startPos: 0
                    onPressed: (m) => { grab = bar.vertical ? mapToItem(bar, m.x, m.y).y : mapToItem(bar, m.x, m.y).x; startPos = bar.position }
                    onPositionChanged: (m) => {
                        if (!pressed) return
                        const g = bar.vertical ? mapToItem(bar, m.x, m.y).y : mapToItem(bar, m.x, m.y).x
                        const ratio = (bar.total - bar.pageSize) / Math.max(1, bar.track - thumb.len)
                        bar.scrolled(Math.max(0, Math.min(bar.total - bar.pageSize, startPos + (g - grab) * ratio)))
                    }
                }
            }
            Repeater {
                model: [0, 1]
                Rectangle {
                    required property int modelData
                    x: bar.vertical ? 1 : (modelData === 0 ? 1 : bar.width - 17)
                    y: bar.vertical ? (modelData === 0 ? 1 : bar.height - 17) : 1
                    width: bar.vertical ? bar.width - 2 : 16
                    height: bar.vertical ? 16 : bar.height - 2
                    color: arMa.containsMouse ? "#e3f1fb" : "transparent"
                    border.color: arMa.containsMouse ? "#3c7fb1" : "transparent"
                    radius: 2
                    Text {
                        anchors.centerIn: parent
                        font.pixelSize: 8
                        color: "#4d4d4d"
                        text: bar.vertical ? (parent.modelData === 0 ? "▲" : "▼") : (parent.modelData === 0 ? "◀" : "▶")
                    }
                    MouseArea {
                        id: arMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: bar.scrolled(Math.max(0, Math.min(bar.total - bar.pageSize, bar.position + (parent.modelData === 0 ? -40 : 40))))
                    }
                }
            }
        }
        Bar {
            id: hBar
            visible: area.needH
            x: flick.x; y: parent.height - height
            width: flick.width; height: 17
            position: flick.contentX
            pageSize: flick.width
            total: flick.contentWidth
            onScrolled: (p) => flick.contentX = p
        }
        Bar {
            id: vBar
            vertical: true
            visible: area.needV
            x: parent.width - width; y: flick.y
            width: 17; height: flick.height
            position: flick.contentY
            pageSize: flick.height
            total: flick.contentHeight
            onScrolled: (p) => flick.contentY = p
        }
        Rectangle { visible: hBar.visible && vBar.visible; x: vBar.x; y: hBar.y; width: 17; height: 17; color: "#eceff3" }
    }

    function paintRuler(ctx, length, thick, offset, horizontal) {
        ctx.reset()
        ctx.fillStyle = "#f4f7fb"
        ctx.fillRect(0, 0, horizontal ? length : thick, horizontal ? thick : length)
        ctx.strokeStyle = "#b8c7da"
        ctx.beginPath()
        if (horizontal) { ctx.moveTo(0, thick - 0.5); ctx.lineTo(length, thick - 0.5) }
        else { ctx.moveTo(thick - 0.5, 0); ctx.lineTo(thick - 0.5, length) }
        ctx.stroke()
        const z = canvas.zoom
        let major = 100
        while (major * z > 160 && major > 10) major /= 2
        while (major * z < 50) major *= 2
        const minor = major / 10
        ctx.strokeStyle = "#6f7f93"
        ctx.fillStyle = "#3b4a5c"
        ctx.font = "9px sans-serif"
        ctx.beginPath()
        const start = Math.floor(offset / z / minor) * minor
        for (let v = Math.max(0, start); v * z - offset < length; v += minor) {
            const pos = Math.round(v * z - offset) + 0.5
            const isMajor = Math.abs(v / major - Math.round(v / major)) < 1e-6
            const isHalf = Math.abs(v / (major / 2) - Math.round(v / (major / 2))) < 1e-6
            const t = isMajor ? thick - 2 : isHalf ? 6 : 3
            if (horizontal) { ctx.moveTo(pos, thick - 1); ctx.lineTo(pos, thick - 1 - t) }
            else { ctx.moveTo(thick - 1, pos); ctx.lineTo(thick - 1 - t, pos) }
            if (isMajor && v > 0) {
                if (horizontal) ctx.fillText(String(Math.round(v)), pos + 2, 9)
                else { ctx.save(); ctx.translate(9, pos + 2); ctx.rotate(Math.PI / 2); ctx.fillText(String(Math.round(v)), 0, 0); ctx.restore() }
            }
        }
        ctx.stroke()
        if (app.hoverPos.x >= 0) { // pointer marker
            ctx.strokeStyle = "#1e5bb4"
            ctx.beginPath()
            const m = Math.round((horizontal ? app.hoverPos.x : app.hoverPos.y) * z - offset) + 0.5
            if (horizontal) { ctx.moveTo(m, 0); ctx.lineTo(m, thick) } else { ctx.moveTo(0, m); ctx.lineTo(thick, m) }
            ctx.stroke()
        }
    }

    // ================================================================ status bar
    Rectangle {
        id: status
        visible: app.showStatus
        anchors.bottom: parent.bottom
        width: parent.width; height: 25
        gradient: Gradient {
            GradientStop { position: 0; color: "#f3f6fb" }
            GradientStop { position: 1; color: "#dbe5f2" }
        }
        Rectangle { width: parent.width; height: 1; color: "#b6c6da" }
        component Cell: Item {
            property string icon: ""
            property string label: ""
            width: 140; height: status.height
            AppIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 16; name: Theme.icon(parent.icon) }
            VText { x: 30; anchors.verticalCenter: parent.verticalCenter; text: parent.label; color: "#1e395b" }
            Rectangle { anchors.right: parent.right; y: 4; width: 1; height: parent.height - 7; color: "#b6c6da" }
            Rectangle { anchors.right: parent.right; anchors.rightMargin: -1; y: 4; width: 1; height: parent.height - 7; color: "#ffffff" }
        }
        Row {
            Cell {
                icon: "paint-status-cursor"
                label: app.hoverPos.x >= 0 && app.hoverPos.x < canvas.imageWidth && app.hoverPos.y < canvas.imageHeight
                       ? Math.floor(app.hoverPos.x) + ", " + Math.floor(app.hoverPos.y) + "px" : ""
            }
            Cell {
                icon: "paint-status-selection"
                label: selGhost.visible ? selGhost.r.width + " × " + selGhost.r.height + "px"
                     : app.selecting && app.rubber.width > 0 ? app.rubber.width + " × " + app.rubber.height + "px"
                     : canvas.hasSelection ? canvas.selection.width + " × " + canvas.selection.height + "px" : ""
            }
            Cell {
                icon: "paint-status-size"
                width: 160
                label: resizeGhost.visible ? resizeGhost.size.width + " × " + resizeGhost.size.height + "px"
                                           : canvas.imageWidth + " × " + canvas.imageHeight + "px"
            }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 10
            height: parent.height
            spacing: 4
            VText {
                width: 44
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: Math.round(canvas.zoom * 1000) / 10 + "%"
                color: "#1e395b"
            }
            component ZoomKey: Rectangle {
                property string glyph: ""
                signal hit()
                width: 17; height: 17
                radius: 8.5
                anchors.verticalCenter: parent.verticalCenter
                border.color: zkMa.containsMouse ? "#3c7fb1" : "#8ea4c1"
                gradient: Gradient {
                    GradientStop { position: 0; color: zkMa.containsMouse ? "#eaf6fd" : "#fbfcfe" }
                    GradientStop { position: 1; color: zkMa.containsMouse ? "#a7d9f5" : "#d5e1f0" }
                }
                Text { anchors.centerIn: parent; anchors.verticalCenterOffset: -1; text: parent.glyph; font.pixelSize: 13; font.bold: true; color: "#2b4c78" }
                MouseArea { id: zkMa; anchors.fill: parent; hoverEnabled: true; onClicked: parent.hit() }
            }
            ZoomKey { glyph: "−"; onHit: app.zoomStep(-1) }
            Slider7 {
                id: zoomSlider
                width: 110
                anchors.verticalCenter: parent.verticalCenter
                from: 0; to: 1; stepSize: 0
                value: canvas.zoom >= 1 ? 0.5 + Math.log(canvas.zoom) / Math.log(8) / 2 : 0.5 - Math.log(1 / canvas.zoom) / Math.log(8) / 2
                onMoved: (v) => {
                    let z = v >= 0.5 ? Math.pow(8, (v - 0.5) * 2) : 1 / Math.pow(8, (0.5 - v) * 2)
                    if (Math.abs(v - 0.5) < 0.03) z = 1
                    app.zoomTo(z)
                }
            }
            ZoomKey { glyph: "+"; onHit: app.zoomStep(1) }
        }
    }

    // ================================================================ popups
    MouseArea { // click-away for app popups
        anchors.fill: parent
        visible: app.popup.length > 0
        acceptedButtons: Qt.AllButtons
        onPressed: app.popup = ""
    }
    component PopupFrame: Item {
        default property alias content: inner.data
        RectangularGlow { anchors.fill: parent; glowRadius: 5; spread: 0.1; cornerRadius: 6; color: "#55000000" }
        Rectangle {
            id: inner
            anchors.fill: parent
            color: "#fafcfe"
            border.color: "#8ea4c1"
        }
    }
    PopupFrame {
        visible: app.popup === "group"
        x: Math.max(4, Math.min(app.popupPos.x, app.width - width - 4))
        y: app.popupPos.y
        width: groupHost.childrenRect.width + 16
        height: groupHost.childrenRect.height + 34
        Item {
            id: groupHost
            x: 8; y: 6
            width: childrenRect.width
            height: childrenRect.height
        }
        VText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 5
            text: app.poppedGroup ? app.poppedGroup.title : ""
            color: "#3b5577"
            font.pixelSize: 11
        }
    }
    PopupFrame {
        visible: app.popup === "brushes"
        x: Math.min(app.popupPos.x, app.width - width - 4)
        y: app.popupPos.y
        width: 3 * 52 + 8; height: 3 * 52 + 8
        Grid {
            x: 4; y: 4
            columns: 3
            Repeater {
                model: app.brushes
                Item {
                    id: bi
                    required property var modelData
                    width: 52; height: 52
                    readonly property bool on: app.brushStyle === modelData[0]
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 2
                        visible: bi.on || biMa.containsMouse
                        color: bi.on ? "#c4dcf7" : "#e8f2fd"
                        border.color: bi.on ? "#6d98cc" : "#a7c5e9"
                    }
                    PaintGlyph { anchors.centerIn: parent; width: 44; height: 40; brush: bi.modelData[0]; color: "#1e1e1e" }
                    MouseArea {
                        id: biMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { app.brushStyle = bi.modelData[0]; app.popup = ""; Shell.hideTooltip(); app.setTool("brush") }
                        onContainsMouseChanged: {
                            if (containsMouse) { const p = bi.mapToItem(Shell.root, 0, bi.height - 16); Shell.showTooltip(bi.modelData[1], p.x, p.y) }
                            else Shell.hideTooltip()
                        }
                    }
                }
            }
        }
    }
    PopupFrame {
        visible: app.popup === "size"
        x: Math.min(app.popupPos.x, app.width - width - 4)
        y: app.popupPos.y
        width: 150; height: 4 * 30 + 8
        Column {
            x: 4; y: 4
            Repeater {
                model: app.sizeKind.length ? app.sizeTables[app.sizeKind] : []
                Item {
                    id: si
                    required property int modelData
                    required property int index
                    width: 142; height: 30
                    readonly property bool on: app.sizeKind.length > 0 && app.sizeChoice[app.sizeKind] === index
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1
                        radius: 2
                        visible: si.on || siMa.containsMouse
                        color: si.on ? "#c4dcf7" : "#e8f2fd"
                        border.color: si.on ? "#6d98cc" : "#a7c5e9"
                    }
                    Rectangle {
                        x: 10; width: 86
                        anchors.verticalCenter: parent.verticalCenter
                        height: Math.min(14, si.modelData)
                        radius: app.sizeKind === "pencil" || app.sizeKind === "eraser" ? 0 : height / 2
                        color: "#1e1e1e"
                    }
                    VText { x: 104; anchors.verticalCenter: parent.verticalCenter; text: si.modelData + "px"; color: "#1e395b" }
                    MouseArea {
                        id: siMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            const c = Object.assign({}, app.sizeChoice)
                            c[app.sizeKind] = si.index
                            app.sizeChoice = c
                            app.popup = ""
                        }
                    }
                }
            }
        }
    }

    // ---- Paint menu
    PopupFrame {
        id: appMenu
        visible: app.popup === "appmenu"
        x: 3; y: tabRow.height - 1
        width: 450; height: 384
        component MenuItem: Item {
            id: mi
            property string icon: ""
            property string label: ""
            property bool submenu: false
            property string pane: "recent"
            signal triggered()
            width: 206; height: 42
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: 3
                visible: miMa.containsMouse
                border.color: "#a7c5e9"
                gradient: Gradient {
                    GradientStop { position: 0; color: "#fbfdff" }
                    GradientStop { position: 1; color: "#dbe9fa" }
                }
            }
            AppIcon { x: 8; anchors.verticalCenter: parent.verticalCenter; size: 32; name: Theme.icon(mi.icon); sourceSize: Qt.size(32, 32) }
            VText { x: 48; anchors.verticalCenter: parent.verticalCenter; text: mi.label; color: "#1e1e1e" }
            Text { visible: mi.submenu; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: "▸"; color: "#4c607a" }
            MouseArea {
                id: miMa
                anchors.fill: parent
                hoverEnabled: true
                onContainsMouseChanged: if (containsMouse) app.appMenuPane = mi.pane
                onClicked: mi.triggered()
            }
        }
        Rectangle { // left column
            x: 1; y: 1
            width: 212; height: parent.height - 38
            color: "#ffffff"
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#d5dfec" }
            Column {
                x: 3; y: 3
                MenuItem { icon: "paint-new"; label: "New"; onTriggered: app.newImage() }
                MenuItem { icon: "paint-open"; label: "Open"; onTriggered: app.openFile() }
                MenuItem { icon: "paint-save"; label: "Save"; onTriggered: { app.popup = ""; app.save() } }
                MenuItem { icon: "paint-save"; label: "Save as"; submenu: true; pane: "saveas"; onTriggered: app.saveAs() }
                Item { width: 1; height: 4 }
                MenuItem { icon: "image-file"; label: "Set as desktop background"; pane: "recent"; enabled: app.path.length > 0; opacity: enabled ? 1 : 0.45
                           onTriggered: { app.popup = ""; app.save(() => { Prefs.wallpaper = app.path }) } }
                MenuItem { icon: "paint-properties"; label: "Properties"; onTriggered: { app.popup = ""; propertiesDialog.show() } }
                MenuItem { icon: "paint-about"; label: "About Paint"; onTriggered: { app.popup = ""; aboutDialog.open = true } }
                Item { width: 1; height: 4 }
                MenuItem { icon: "paint-exit"; label: "Exit"; onTriggered: app.exit() }
            }
        }
        Item { // right pane
            x: 216; y: 4
            width: parent.width - x - 4; height: parent.height - 44
            VText { x: 6; y: 4; text: app.appMenuPane === "saveas" ? "Save as" : "Recent pictures"; font.bold: true; color: "#1e395b" }
            Rectangle { x: 6; y: 24; width: parent.width - 12; height: 1; color: "#d5dfec" }
            Column {
                visible: app.appMenuPane === "recent"
                x: 2; y: 30
                width: parent.width - 4
                Repeater {
                    model: app.recent
                    HoverItem {
                        required property string modelData
                        required property int index
                        width: parent.width; height: 24
                        VText { x: 6; width: parent.width - 12; anchors.verticalCenter: parent.verticalCenter; text: (index + 1) + "  " + Files.fileName(modelData) }
                        onClicked: { app.popup = ""; const p = modelData; app.confirmThen(() => app.loadFile(p)) }
                    }
                }
            }
            Column {
                visible: app.appMenuPane === "saveas"
                x: 2; y: 30
                width: parent.width - 4
                Repeater {
                    model: [["PNG picture", "Save a photograph or drawing with high quality and use it on your computer or on the web.", 0],
                            ["JPEG picture", "Save a photograph with good quality and use it on your computer, in e-mail, or on the web.", 1],
                            ["BMP picture", "Save any kind of picture with high quality and use it on your computer.", 2],
                            ["Other formats", "Open the Save As dialog box to select from all possible file types.", 3]]
                    HoverItem {
                        id: sa
                        required property var modelData
                        width: parent.width; height: 58
                        VText { x: 8; y: 6; text: sa.modelData[0]; font.bold: true }
                        VText { x: 8; y: 23; width: parent.width - 16; text: sa.modelData[1]; wrapMode: Text.Wrap; maximumLineCount: 2; color: Theme.textMuted; font.pixelSize: 11 }
                        onClicked: app.saveAs(sa.modelData[2])
                    }
                }
            }
        }
        Rectangle { // footer
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 1
            x: 1
            width: parent.width - 2; height: 36
            color: "#e9eff7"
            Rectangle { width: parent.width; height: 1; color: "#d5dfec" }
            Button7 {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: "Exit"
                iconName: Theme.icon("paint-exit")
                onClicked: app.exit()
            }
        }
    }

    // ================================================================ dialogs
    PaintFileDialog {
        id: fileDialog
        tracking: app.frame
        property var afterSave: null
        property bool pasteMode: false
        onAccepted: (p, t) => {
            if (mode === "save") {
                if (canvas.save(p)) {
                    app.loadedPath = p
                    app.path = p
                    app.addRecent(p)
                    const after = afterSave
                    afterSave = null
                    if (after)
                        after()
                } else {
                    Shell.notify("Paint could not save the picture", p, Theme.icon("paint"))
                }
            } else if (pasteMode) {
                pasteMode = false
                if (canvas.pasteFrom(p, 0, 0))
                    app.setTool("select")
            } else {
                app.cancelPending()
                app.loadFile(p)
            }
        }
        onRejected: pasteMode = false
    }
    PaintColorDialog {
        id: colorDialog
        tracking: app.frame
        onAccepted: (c) => {
            if (app.activeColor === 1) app.color1 = c
            else app.color2 = c
            const cc = app.customColors.slice()
            const hex = c.toString()
            if (cc.indexOf(hex) < 0) {
                let slot = cc.indexOf("")
                if (slot < 0) { cc.shift(); cc.push(hex) } else cc[slot] = hex
                app.customColors = cc
            }
        }
    }
    PaintDialog {
        id: resizeDialog
        title: "Resize and Skew"
        tracking: app.frame
        clientWidth: 300
        clientHeight: 330
        property bool percent: true
        property bool keepAspect: true
        property int baseW: 1
        property int baseH: 1
        function show() {
            app.commitPending()
            baseW = canvas.hasSelection ? canvas.selection.width : canvas.imageWidth
            baseH = canvas.hasSelection ? canvas.selection.height : canvas.imageHeight
            percent = true
            rw.text = "100"; rh.text = "100"; skh.text = "0"; skv.text = "0"
            open = true
            rw.input.forceActiveFocus()
            rw.input.selectAll()
        }
        function sync(fromW) {
            if (!keepAspect)
                return
            const src = fromW ? rw : rh, dst = fromW ? rh : rw
            const v = parseFloat(src.text)
            if (isNaN(v))
                return
            if (percent) dst.text = String(Math.round(v))
            else dst.text = String(Math.max(1, Math.round(fromW ? v * baseH / baseW : v * baseW / baseH)))
        }
        function apply() {
            const a = parseFloat(rw.text), b = parseFloat(rh.text)
            if (isNaN(a) || isNaN(b) || a <= 0 || b <= 0)
                return
            const w = percent ? Math.round(baseW * a / 100) : Math.round(a)
            const h = percent ? Math.round(baseH * b / 100) : Math.round(b)
            open = false
            if (w !== baseW || h !== baseH)
                canvas.resizeImage(w, h)
            const sh = parseFloat(skh.text) || 0, sv = parseFloat(skv.text) || 0
            if (sh !== 0 || sv !== 0)
                canvas.skew(Math.max(-89, Math.min(89, sh)), Math.max(-89, Math.min(89, sv)))
        }
        onRejected: open = false
        component Section: Item {
            property string title: ""
            width: 276; x: 12
            Rectangle { y: 8; width: parent.width; height: parent.height - 8; color: "transparent"; border.color: "#d5dfe5"; radius: 3 }
            Rectangle { x: 8; y: 0; width: st.implicitWidth + 8; height: 16; color: Theme.face; VText { id: st; x: 4; text: parent.parent.title; color: "#1e395b" } }
        }
        component Radio: Item {
            property string text: ""
            property bool checked: false
            signal picked()
            width: rt.implicitWidth + 22; height: 20
            Rectangle {
                width: 13; height: 13; radius: 6.5
                anchors.verticalCenter: parent.verticalCenter
                border.color: rMa.containsMouse ? "#3c7fb1" : "#8e8f8f"
                gradient: Gradient {
                    GradientStop { position: 0; color: "#ebebeb" }
                    GradientStop { position: 1; color: "#ffffff" }
                }
                Rectangle { anchors.centerIn: parent; width: 7; height: 7; radius: 3.5; visible: parent.parent.checked; color: "#2a5ea8" }
            }
            VText { id: rt; x: 19; anchors.verticalCenter: parent.verticalCenter; text: parent.text }
            MouseArea { id: rMa; anchors.fill: parent; hoverEnabled: true; onClicked: parent.picked() }
        }
        component NumField: Row {
            property string label: ""
            property string icon: ""
            property alias field: tf
            property alias text: tf.text
            signal edited()
            spacing: 8
            height: 26
            AppIcon { size: 16; name: Theme.icon(parent.icon); anchors.verticalCenter: parent.verticalCenter }
            VText { width: 80; text: parent.label; anchors.verticalCenter: parent.verticalCenter }
            TextField7 {
                id: tf
                width: 80
                anchors.verticalCenter: parent.verticalCenter
                input.validator: DoubleValidator { bottom: -100000; top: 100000 }
                onTextChanged: if (input.activeFocus) parent.edited()
                onAccepted: resizeDialog.apply()
            }
        }
        Section {
            y: 8; height: 158
            title: "Resize"
            Row {
                x: 14; y: 26; spacing: 12
                VText { text: "By:"; anchors.verticalCenter: parent.verticalCenter }
                Radio { text: "Percentage"; checked: resizeDialog.percent; onPicked: { resizeDialog.percent = true; rw.text = "100"; rh.text = "100" } }
                Radio { text: "Pixels"; checked: !resizeDialog.percent; onPicked: { resizeDialog.percent = false; rw.text = String(resizeDialog.baseW); rh.text = String(resizeDialog.baseH) } }
            }
            Column {
                x: 14; y: 56
                NumField { id: rwRow; label: "Horizontal:"; icon: "paint-fliph"; onEdited: resizeDialog.sync(true) }
                NumField { id: rhRow; label: "Vertical:"; icon: "paint-flipv"; onEdited: resizeDialog.sync(false) }
                Item { width: 1; height: 4 }
                CheckBox7 { text: "Maintain aspect ratio"; checked: resizeDialog.keepAspect; onToggled: (c) => { resizeDialog.keepAspect = c; if (c) resizeDialog.sync(true) } }
            }
        }
        Section {
            y: 174; height: 110
            title: "Skew (Degrees)"
            Column {
                x: 14; y: 28
                NumField { id: skhRow; label: "Horizontal:"; icon: "paint-fliph" }
                NumField { id: skvRow; label: "Vertical:"; icon: "paint-flipv" }
            }
        }
        readonly property var rw: rwRow.field
        readonly property var rh: rhRow.field
        readonly property var skh: skhRow.field
        readonly property var skv: skvRow.field
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            y: 296
            spacing: 8
            Button7 { text: "OK"; isDefault: true; onClicked: resizeDialog.apply() }
            Button7 { text: "Cancel"; onClicked: resizeDialog.open = false }
        }
    }
    PaintDialog {
        id: propertiesDialog
        title: "Image Properties"
        tracking: app.frame
        clientWidth: 330
        clientHeight: 300
        property string unit: "px"
        property bool blackWhite: false
        function show() {
            app.commitPending()
            unit = "px"
            blackWhite = false
            pw.text = String(canvas.imageWidth)
            ph.text = String(canvas.imageHeight)
            open = true
        }
        function factor(u) { return u === "in" ? 96 : u === "cm" ? 96 / 2.54 : 1 }
        function convert(u) {
            const f0 = factor(unit), f1 = factor(u)
            pw.text = String(Math.round(parseFloat(pw.text) * f0 / f1 * 100) / 100)
            ph.text = String(Math.round(parseFloat(ph.text) * f0 / f1 * 100) / 100)
            unit = u
        }
        onRejected: open = false
        Column {
            x: 14; y: 12
            spacing: 4
            VText { text: "File attributes"; color: "#1e395b"; font.bold: true }
            VText { text: "Last saved:\t" + (app.path.length && Files.exists(app.path) ? Files.info(app.path).modified : "Not available") }
            VText { text: "Size on disk:\t" + (app.path.length && Files.exists(app.path) ? Files.info(app.path).size : "Not available") }
            VText { text: "Resolution:\t96 DPI" }
            Item { width: 1; height: 8 }
            component Choice: Item {
                property string label: ""
                property bool on: false
                signal picked()
                width: cl.implicitWidth + 22; height: 20
                Rectangle {
                    width: 13; height: 13; radius: 6.5
                    anchors.verticalCenter: parent.verticalCenter
                    border.color: "#8e8f8f"
                    color: "white"
                    Rectangle { anchors.centerIn: parent; width: 7; height: 7; radius: 3.5; visible: parent.parent.on; color: "#2a5ea8" }
                }
                VText { id: cl; x: 19; anchors.verticalCenter: parent.verticalCenter; text: parent.label }
                MouseArea { anchors.fill: parent; onClicked: parent.picked() }
            }
            VText { text: "Units"; color: "#1e395b"; font.bold: true }
            Row {
                spacing: 12
                Repeater {
                    model: [["in", "Inches"], ["cm", "Centimeters"], ["px", "Pixels"]]
                    Item {
                        required property var modelData
                        width: ur.implicitWidth + 22; height: 20
                        Rectangle {
                            width: 13; height: 13; radius: 6.5
                            anchors.verticalCenter: parent.verticalCenter
                            border.color: "#8e8f8f"
                            color: "white"
                            Rectangle { anchors.centerIn: parent; width: 7; height: 7; radius: 3.5; visible: propertiesDialog.unit === parent.parent.modelData[0]; color: "#2a5ea8" }
                        }
                        VText { id: ur; x: 19; anchors.verticalCenter: parent.verticalCenter; text: parent.modelData[1] }
                        MouseArea { anchors.fill: parent; onClicked: propertiesDialog.convert(parent.modelData[0]) }
                    }
                }
            }
            Item { width: 1; height: 8 }
            VText { text: "Colors"; color: "#1e395b"; font.bold: true }
            Row {
                spacing: 12
                Choice { label: "Black and white"; on: propertiesDialog.blackWhite; onPicked: propertiesDialog.blackWhite = true }
                Choice { label: "Color"; on: !propertiesDialog.blackWhite; onPicked: propertiesDialog.blackWhite = false }
            }
            Item { width: 1; height: 8 }
            Row {
                spacing: 8
                VText { text: "Width:"; anchors.verticalCenter: parent.verticalCenter; width: 46 }
                TextField7 { id: pw; width: 70 }
                VText { text: "Height:"; anchors.verticalCenter: parent.verticalCenter; width: 46 }
                TextField7 { id: ph; width: 70 }
            }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            y: 266
            spacing: 8
            Button7 { text: "Default"; onClicked: { propertiesDialog.unit = "px"; pw.text = "800"; ph.text = "600" } }
            Button7 {
                text: "OK"; isDefault: true
                onClicked: {
                    const f = propertiesDialog.factor(propertiesDialog.unit)
                    const w = Math.round(parseFloat(pw.text) * f), h = Math.round(parseFloat(ph.text) * f)
                    propertiesDialog.open = false
                    if (w > 0 && h > 0)
                        canvas.resizeCanvas(w, h)
                    if (propertiesDialog.blackWhite)
                        canvas.blackAndWhite()
                }
            }
            Button7 { text: "Cancel"; onClicked: propertiesDialog.open = false }
        }
    }
    PaintDialog {
        id: aboutDialog
        title: "About Paint"
        tracking: app.frame
        clientWidth: 380
        clientHeight: 190
        onRejected: open = false
        Rectangle { width: parent.width; height: 64; color: "white" }
        AppIcon { x: 18; y: 12; size: 48; name: Theme.icon("paint") }
        VText { x: 80; y: 16; text: "Paint"; font.pixelSize: 20; color: "#1e395b" }
        VText { x: 80; y: 42; text: "Vitrum " + Session.version; color: Theme.textMuted }
        VText {
            x: 18; y: 80; width: parent.width - 36
            wrapMode: Text.Wrap
            text: "A simple raster image editor that comes with Vitrum. Licensed under the GNU General Public License, version 3 or later."
        }
        Button7 { anchors.right: parent.right; anchors.rightMargin: 12; y: 152; text: "OK"; isDefault: true; onClicked: aboutDialog.open = false }
    }
    PaintDialog {
        id: savePrompt
        title: "Paint"
        tracking: app.frame
        clientWidth: 380
        clientHeight: 120
        onRejected: { open = false; app.pendingAction = null }
        Rectangle { width: parent.width; height: 76; color: "white" }
        VText {
            x: 18; y: 22; width: parent.width - 36
            text: "Do you want to save changes to " + app.docName + "?"
            color: "#003399"
            font.pixelSize: 15
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            y: 87
            spacing: 8
            Button7 {
                text: "Save"; isDefault: true
                onClicked: {
                    savePrompt.open = false
                    const a = app.pendingAction
                    app.pendingAction = null
                    app.save(a)
                }
            }
            Button7 {
                text: "Don't Save"
                onClicked: {
                    savePrompt.open = false
                    const a = app.pendingAction
                    app.pendingAction = null
                    canvas.modified = false
                    if (a) a()
                }
            }
            Button7 { text: "Cancel"; onClicked: { savePrompt.open = false; app.pendingAction = null } }
        }
    }

    // ================================================================ full screen view
    Component {
        id: fullScreenComponent
        FocusScope {
            id: fs
            property var source: null
            anchors.fill: parent
            z: 100000
            Component.onCompleted: {
                fsCanvas.copyFrom(source, Qt.rect(0, 0, source.imageWidth, source.imageHeight), [])
                fsCanvas.zoom = Math.min(1, width / source.imageWidth, height / source.imageHeight)
                forceActiveFocus()
            }
            Keys.onPressed: (e) => { e.accepted = true; app.exitFullScreen() }
            Rectangle { anchors.fill: parent; color: "#1b1b1b" }
            PaintCanvas { id: fsCanvas; anchors.centerIn: parent }
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onClicked: app.exitFullScreen() }
        }
    }
}
