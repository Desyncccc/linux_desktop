import QtQuick
import QtWayland.Compositor as WL
import QtWayland.Compositor.XdgShell as Xdg
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// A managed top-level window: either a Wayland xdg_toplevel or one of the
// shell's built-in apps. Draws the glass frame for server-side decorated
// windows and implements move/resize/snap/maximize/minimize.
Item {
    id: win

    // ---- source
    property var xdgSurface: null
    readonly property var toplevel: xdgSurface ? xdgSurface.toplevel : null
    readonly property var surface: xdgSurface ? xdgSurface.surface : null
    property Component internalComponent: null
    property var internalProps: ({})
    property string internalKind: ""
    readonly property bool isInternal: internalComponent !== null
    property string internalTitle: ""
    property string internalIcon: ""
    property bool internalResizable: true
    property bool internalMaximizable: true
    property real internalWidth: 640
    property real internalHeight: 480
    property real internalMinWidth: 220
    property real internalMinHeight: 120
    property bool internalMaximized: false
    // Some built-in windows (Explorer) leave the caption empty, like the
    // shell windows of the glass era: the address bar says where you are.
    property bool internalBareCaption: false
    property alias internalItem: internalLoader.item
    property string uid: ""

    // ---- metadata
    readonly property string appId: toplevel ? toplevel.appId : ""
    readonly property string desktopId: { Apps.count; return isInternal ? Apps.idForInternal(internalKind) : Apps.idForAppId(appId) }
    readonly property var appInfo: desktopId !== "" ? Apps.get(desktopId) : ({})
    readonly property string appName: isInternal ? internalTitle : (appInfo.name || appId || "Application")
    readonly property string title: isInternal ? internalTitle : (toplevel && toplevel.title ? toplevel.title : appName)
    readonly property string iconSource: isInternal ? internalIcon : Theme.themeIcon(appInfo.iconName || appId, "application-x-executable")
    readonly property string groupKey: isInternal ? desktopId
                                       : (desktopId !== "" ? desktopId : (appId !== "" ? "app:" + appId : "win:" + uid))

    // ---- state
    property bool minimized: false
    property bool closing: false
    property string tile: ""
    property rect restoreRect: Qt.rect(0, 0, 0, 0)   // frame position + content size
    property bool placed: false
    property bool constructed: false
    readonly property bool maximized: isInternal ? internalMaximized : (toplevel ? toplevel.maximized : false)
    readonly property bool fullscreen: toplevel ? toplevel.fullscreen : false
    readonly property bool active: Shell.activeWindow === win
    readonly property bool decorated: isInternal || (toplevel !== null && toplevel.decorationMode === Xdg.XdgToplevel.ServerSideDecoration)
                                      || (ServerDecorations.revision >= 0 && surface !== null && ServerDecorations.isServerDecorated(surface))
    readonly property bool framed: decorated && !fullscreen
    readonly property bool resizable: isInternal ? internalResizable
                                      : !(toplevel && toplevel.maxSize.width > 0 && toplevel.maxSize.width === toplevel.minSize.width
                                          && toplevel.maxSize.height === toplevel.minSize.height)
    readonly property bool canMaximize: isInternal ? internalMaximizable : resizable
    readonly property real bw: framed && !maximized ? Theme.frameBorder : 0
    readonly property real th: framed ? (maximized ? Theme.titleHeightMaximized : Theme.titleHeight) : 0
    readonly property rect geom: xdgSurface && xdgSurface.windowGeometry.width > 0 ? xdgSurface.windowGeometry
                                                                                   : Qt.rect(0, 0, surfaceItem.width, surfaceItem.height)
    readonly property real contentWidth: isInternal ? internalWidth : geom.width
    readonly property real contentHeight: isInternal ? internalHeight : geom.height
    readonly property Item thumbnailSource: chrome

    width: contentWidth + 2 * bw
    height: contentHeight + th + bw
    visible: contentWidth > 0 && contentHeight > 0
    enabled: !minimized && !closing

    // ---- animations
    property real appear: 0
    property real minimizeProgress: minimized ? 1 : 0
    Behavior on minimizeProgress { NumberAnimation { duration: Theme.anim(220); easing.type: Easing.InOutQuad } }
    NumberAnimation on appear { id: appearAnim; from: 0; to: 1; duration: Theme.anim(200); easing.type: Easing.OutCubic; running: false }
    NumberAnimation {
        id: closeAnim
        target: win; property: "appear"; to: 0
        duration: Theme.anim(160); easing.type: Easing.InCubic
        onFinished: { Shell.removeWindow(win); win.destroy() }
    }
    opacity: appear * (1 - minimizeProgress)
    transform: [
        Scale {
            origin.x: win.width / 2
            origin.y: win.height / 2
            xScale: (0.93 + 0.07 * win.appear) * (1 - 0.45 * win.minimizeProgress)
            yScale: xScale
        },
        Translate { y: win.minimizeProgress * Math.max(0, Shell.screenHeight - win.y - win.height * 0.3) }
    ]

    Component.onCompleted: {
        appearAnim.start()
        constructed = true
        placeIfNeeded()
    }

    // ---- placement
    function placeIfNeeded() {
        if (!constructed || placed || contentWidth <= 0 || contentHeight <= 0)
            return
        placed = true
        const a = Shell.workArea
        let parentWin = null
        if (toplevel && toplevel.parentToplevel)
            parentWin = Shell.windowForSurface(toplevel.parentToplevel.xdgSurface.surface)
        if (parentWin) {
            x = parentWin.x + (parentWin.width - width) / 2
            y = parentWin.y + (parentWin.height - height) / 2
        } else {
            const n = Shell.windows.length % 8
            x = a.x + (a.width - width) / 2 + (n - 3) * 22
            y = a.y + Math.max(0, (a.height - height) / 2 - 30) + (n - 3) * 18
        }
        x = Math.max(a.x, Math.min(x, a.x + a.width - width))
        y = Math.max(a.y, Math.min(y, a.y + a.height - Math.min(height, 80)))
        if (width > a.width || height > a.height)
            Qt.callLater(maximize)
    }

    // ---- focus
    function takeFocus() {
        if (isInternal) {
            if (internalLoader.item)
                internalLoader.item.forceActiveFocus()
        } else if (surfaceItem.surface) {
            surfaceItem.takeFocus()
        }
    }

    function xdgStates() {
        return active ? [Xdg.XdgToplevel.ActivatedState] : []
    }

    function configureContent(w, h) {
        w = Math.round(w); h = Math.round(h)
        if (isInternal) {
            internalWidth = Math.max(internalMinWidth, w)
            internalHeight = Math.max(internalMinHeight, h)
        } else if (toplevel) {
            toplevel.sendConfigure(Qt.size(w, h), xdgStates())
        }
    }

    function saveRestore() {
        if (!maximized && tile === "" && !fullscreen)
            restoreRect = Qt.rect(x, y, contentWidth, contentHeight)
    }

    function maximize() {
        if (maximized || !canMaximize)
            return
        saveRestore()
        tile = ""
        const a = Shell.workArea
        if (isInternal) {
            internalMaximized = true
            internalWidth = a.width
            internalHeight = a.height - Theme.titleHeightMaximized
        } else if (toplevel) {
            toplevel.sendMaximized(Qt.size(a.width, a.height - (decorated ? Theme.titleHeightMaximized : 0)))
        }
        x = a.x
        y = a.y
    }

    function restore() {
        if (maximized || fullscreen) {
            if (isInternal) {
                internalMaximized = false
                internalWidth = restoreRect.width
                internalHeight = restoreRect.height
            } else if (toplevel) {
                if (fullscreen)
                    toplevel.sendConfigure(Qt.size(restoreRect.width, restoreRect.height), xdgStates())
                else
                    toplevel.sendUnmaximized(Qt.size(restoreRect.width, restoreRect.height))
            }
            x = restoreRect.x
            y = restoreRect.y
        } else if (tile !== "") {
            tile = ""
            configureContent(restoreRect.width, restoreRect.height)
            x = restoreRect.x
            y = restoreRect.y
        }
    }

    function toggleMaximize() {
        if (maximized)
            restore()
        else
            maximize()
    }

    function snap(name) {
        if (name === "max") {
            maximize()
            return
        }
        if (name === "" || !resizable)
            return
        saveRestore()
        if (isInternal)
            internalMaximized = false
        const r = Shell.tileRect(name)
        tile = name
        const border = decorated ? Theme.frameBorder : 0
        configureContent(r.width - 2 * border, r.height - (decorated ? Theme.titleHeight + Theme.frameBorder : 0))
        x = r.x
        y = r.y
    }

    function restoreForDrag(g, ratio) {
        const wasTile = tile !== ""
        const frameW = restoreRect.width + (decorated ? 2 * Theme.frameBorder : 0)
        if (maximized) {
            if (isInternal) {
                internalMaximized = false
                internalWidth = restoreRect.width
                internalHeight = restoreRect.height
            } else {
                toplevel.sendUnmaximized(Qt.size(restoreRect.width, restoreRect.height))
            }
        } else if (wasTile) {
            configureContent(restoreRect.width, restoreRect.height)
        }
        tile = ""
        x = g.x - ratio * frameW
        y = Math.max(0, g.y - 14)
    }

    function close() {
        if (closing)
            return
        if (isInternal) {
            closing = true
            closeAnim.start()
        } else if (toplevel) {
            toplevel.sendClose()
        }
    }

    function showWindowMenu(gx, gy) {
        Shell.showMenu([
            { text: "Restore", icon: "", enabled: maximized || tile !== "", action: () => win.restore() },
            { text: "Minimize", enabled: true, action: () => Shell.minimize(win) },
            { text: "Maximize", enabled: canMaximize && !maximized, action: () => win.maximize() },
            { text: "Snap left", enabled: resizable, action: () => win.snap("left") },
            { text: "Snap right", enabled: resizable, action: () => win.snap("right") },
            { separator: true },
            { text: "Close\tAlt+F4", bold: true, action: () => win.close() }
        ], gx, gy)
    }

    // ---- interactive resize
    property int resizeEdges: 0
    property point rsStart
    property rect rsRect
    property real anchorRight: 0
    property real anchorBottom: 0

    function beginResize(edges, g) {
        Shell.activate(win)
        if (tile !== "")
            tile = ""
        resizeEdges = edges
        rsStart = g
        rsRect = Qt.rect(x, y, contentWidth, contentHeight)
        anchorRight = x + width
        anchorBottom = y + height
    }

    function updateResize(g) {
        let w = rsRect.width, h = rsRect.height
        const dx = g.x - rsStart.x, dy = g.y - rsStart.y
        if (resizeEdges & Qt.RightEdge) w += dx
        if (resizeEdges & Qt.LeftEdge) w -= dx
        if (resizeEdges & Qt.BottomEdge) h += dy
        if (resizeEdges & Qt.TopEdge) h -= dy
        let minW = isInternal ? internalMinWidth : Math.max(120, toplevel.minSize.width)
        let minH = isInternal ? internalMinHeight : Math.max(40, toplevel.minSize.height)
        let maxW = !isInternal && toplevel.maxSize.width > 0 ? toplevel.maxSize.width : 100000
        let maxH = !isInternal && toplevel.maxSize.height > 0 ? toplevel.maxSize.height : 100000
        w = Math.round(Math.max(minW, Math.min(maxW, w)))
        h = Math.round(Math.max(minH, Math.min(maxH, h)))
        if (isInternal) {
            internalWidth = w
            internalHeight = h
        } else {
            toplevel.sendResizing(Qt.size(w, h))
        }
    }

    function endResize() {
        if (!isInternal && toplevel)
            toplevel.sendConfigure(Qt.size(Math.round(contentWidth), Math.round(contentHeight)), xdgStates())
        resizeEdges = 0
    }

    onWidthChanged: {
        if (resizeEdges & Qt.LeftEdge)
            x = anchorRight - width
        placeIfNeeded()
    }
    onHeightChanged: {
        if (resizeEdges & Qt.TopEdge)
            y = anchorBottom - height
        placeIfNeeded()
    }

    Connections {
        target: win.toplevel
        ignoreUnknownSignals: true
        function onSetMaximized() { win.maximize() }
        function onUnsetMaximized() { win.restore() }
        function onSetMinimized() { Shell.minimize(win) }
        function onSetFullscreen(output) {
            win.saveRestore()
            win.toplevel.sendFullscreen(Qt.size(Shell.screenWidth, Shell.screenHeight))
            win.x = 0
            win.y = 0
            Shell.activate(win)
        }
        function onUnsetFullscreen() { win.restore() }
        function onShowWindowMenu(seat, pos) {
            const g = surfaceItem.mapToItem(Shell.root, pos.x, pos.y)
            win.showWindowMenu(g.x, g.y)
        }
        function onTitleChanged() { Shell.revision++ }
        function onAppIdChanged() { Shell.revision++ }
    }
    onActiveChanged: {
        if (!isInternal && toplevel && resizeEdges === 0 && !maximized && !fullscreen && contentWidth > 0)
            toplevel.sendConfigure(Qt.size(Math.round(contentWidth), Math.round(contentHeight)), xdgStates())
    }

    // ---- Aero Peek outline
    Rectangle {
        anchors.fill: parent
        radius: win.framed && !win.maximized ? Theme.frameRadius : 0
        color: Qt.rgba(1, 1, 1, 0.06)
        border.color: Qt.rgba(1, 1, 1, 0.8)
        opacity: 1 - body.opacity
        visible: opacity > 0.01
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, parent.radius - 1)
            color: "transparent"
            border.color: Qt.rgba(0, 0, 0, 0.35)
        }
    }

    Item {
        id: body
        anchors.fill: parent
        opacity: Shell.peeking && Shell.peekWindow !== win ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.anim(180) } }

        RectangularGlow {
            visible: win.framed && !win.maximized
            x: 2; y: 5
            width: parent.width - 4
            height: parent.height - 4
            glowRadius: Theme.isBasic ? 6 : (win.active ? (Theme.isModern ? 22 : 16) : 10)
            spread: 0.05
            cornerRadius: glowRadius + Theme.frameRadius
            color: win.active ? "#78000000" : "#48000000"
        }

        Item {
            id: chrome
            anchors.fill: parent

            GlassPanel {
                id: frameGlass
                visible: win.framed
                anchors.fill: parent
                tracking: win
                active: win.active
                role: "window"
                radius: win.maximized ? 0 : Theme.frameRadius
                outerOpacity: win.maximized ? 0 : 0.7
            }

            // Title: icon + text with glow
            AppIcon {
                id: titleIcon
                visible: win.framed && !win.internalBareCaption
                x: win.bw + 3
                y: Math.round((win.th - height) / 2) + (win.maximized ? 0 : 1)
                size: 16
                name: win.iconSource
            }
            GlowText {
                visible: win.framed && !win.internalBareCaption
                x: titleIcon.x + 22
                y: titleIcon.y - 1
                width: captions.x - x - 10
                height: 18
                text: win.title
                color: win.active ? Theme.titleText : Theme.titleTextInactive
                font.pixelSize: Theme.fontSize
                glow: Theme.titleGlow
            }

            // Title bar drag area
            MouseArea {
                id: titleDrag
                visible: win.framed
                x: win.bw
                y: 0
                width: win.width - 2 * win.bw
                height: win.th
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                property point pressPos
                property point startWin
                property bool moved: false
                onPressed: (m) => {
                    Shell.activate(win)
                    const g = mapToItem(Shell.root, m.x, m.y)
                    if (m.button === Qt.RightButton) {
                        win.showWindowMenu(g.x, g.y)
                        return
                    }
                    if (m.button === Qt.MiddleButton) {
                        Shell.minimize(win)
                        return
                    }
                    pressPos = g
                    startWin = Qt.point(win.x, win.y)
                    moved = false
                }
                onPositionChanged: (m) => {
                    if (!pressed || !(pressedButtons & Qt.LeftButton))
                        return
                    const g = mapToItem(Shell.root, m.x, m.y)
                    if (!moved && Math.abs(g.x - pressPos.x) + Math.abs(g.y - pressPos.y) < 5)
                        return
                    if (!moved) {
                        moved = true
                        if (win.maximized || win.tile !== "") {
                            win.restoreForDrag(g, m.x / Math.max(1, width))
                            startWin = Qt.point(win.x, win.y)
                            pressPos = g
                        }
                    }
                    win.x = startWin.x + g.x - pressPos.x
                    win.y = Math.max(0, startWin.y + g.y - pressPos.y)
                    const t = Shell.snapTargetAt(g.x, g.y)
                    Shell.snapTarget = (t === "max" && !win.canMaximize) || (t !== "max" && !win.resizable) ? "" : t
                }
                onReleased: {
                    if (moved && Shell.snapTarget !== "")
                        win.snap(Shell.snapTarget)
                    Shell.snapTarget = ""
                    moved = false
                }
                onDoubleClicked: (m) => {
                    if (m.button === Qt.LeftButton && win.canMaximize)
                        win.toggleMaximize()
                }
            }

            // Caption buttons
            Row {
                id: captions
                visible: win.framed
                anchors.right: parent.right
                anchors.rightMargin: Theme.isModern ? win.bw : (win.maximized ? 2 : win.bw - 1)
                y: Theme.isModern ? win.bw : 0
                spacing: Theme.isModern ? 0 : -1
                CaptionButton {
                    width: Theme.isModern ? 46 : 27; height: Theme.isModern ? win.th - win.bw : (win.maximized ? Theme.captionHeight - 1 : Theme.captionHeight)
                    kind: "minimize"
                    active: win.active
                    onClicked: Shell.minimize(win)
                }
                CaptionButton {
                    id: maxButton
                    visible: win.canMaximize
                    width: Theme.isModern ? 46 : 27; height: Theme.isModern ? win.th - win.bw : (win.maximized ? Theme.captionHeight - 1 : Theme.captionHeight)
                    kind: win.maximized ? "restore" : "maximize"
                    active: win.active
                    onClicked: win.toggleMaximize()
                    onHoverHeld: {
                        if (win.resizable) {
                            const p = maxButton.mapToItem(Shell.root, maxButton.width / 2, maxButton.height)
                            Shell.snapLayoutsAnchor = p
                            Shell.snapLayoutsFor = win
                        }
                    }
                }
                CaptionButton {
                    width: 46; height: Theme.isModern ? win.th - win.bw : (win.maximized ? Theme.captionHeight - 1 : Theme.captionHeight)
                    kind: "close"
                    lastInRow: !win.maximized
                    active: win.active
                    onClicked: win.close()
                }
            }

            // Client area border
            Rectangle {
                visible: win.framed && !Theme.isModern
                x: win.bw - 1
                y: win.th - 1
                width: win.contentWidth + 2
                height: win.contentHeight + 2
                color: "transparent"
                border.color: Qt.rgba(0, 0, 0, 0.55)
            }

            Item {
                id: clientArea
                x: win.bw
                y: win.th
                width: win.contentWidth
                height: win.contentHeight
                clip: win.isInternal

                WL.ShellSurfaceItem {
                    id: surfaceItem
                    visible: !win.isInternal
                    x: -win.geom.x
                    y: -win.geom.y
                    shellSurface: win.xdgSurface
                    moveItem: win
                    autoCreatePopupItems: true
                    onSurfaceDestroyed: {
                        bufferLocked = true
                        win.closing = true
                        closeAnim.start()
                    }
                }

                Rectangle {
                    visible: win.isInternal
                    anchors.fill: parent
                    color: Theme.face
                }
                Loader {
                    id: internalLoader
                    anchors.fill: parent
                    sourceComponent: win.internalComponent
                    focus: true
                    onLoaded: {
                        if (item.hasOwnProperty("frame"))
                            item.frame = win
                        for (const k in win.internalProps)
                            if (item.hasOwnProperty(k))
                                item[k] = win.internalProps[k]
                    }
                }
            }

            // Resize handles
            component Handle: MouseArea {
                property int edges: 0
                readonly property real grow: Theme.isModern ? 5 : 0
                hoverEnabled: true
                enabled: win.framed && !win.maximized && win.resizable
                preventStealing: true
                onPressed: (m) => win.beginResize(edges, mapToItem(Shell.root, m.x, m.y))
                onPositionChanged: (m) => { if (pressed) win.updateResize(mapToItem(Shell.root, m.x, m.y)) }
                onReleased: win.endResize()
            }
            Handle { edges: Qt.LeftEdge; cursorShape: Qt.SizeHorCursor; x: -grow; y: 12; width: win.bw + grow; height: win.height - 24 }
            Handle { edges: Qt.RightEdge; cursorShape: Qt.SizeHorCursor; x: win.width - win.bw; y: 12; width: win.bw + grow; height: win.height - 24 }
            Handle { edges: Qt.TopEdge; cursorShape: Qt.SizeVerCursor; x: 12; y: -grow; width: win.width - 24 - (win.width - captions.x); height: 4 + grow }
            Handle { edges: Qt.BottomEdge; cursorShape: Qt.SizeVerCursor; x: 12; y: win.height - win.bw; width: win.width - 24; height: win.bw + grow }
            Handle { edges: Qt.TopEdge | Qt.LeftEdge; cursorShape: Qt.SizeFDiagCursor; x: -grow; y: -grow; width: 12 + grow; height: 12 + grow }
            Handle { edges: Qt.TopEdge | Qt.RightEdge; cursorShape: Qt.SizeBDiagCursor; x: win.width - 6; y: -grow; width: 6 + grow; height: 12 + grow }
            Handle { edges: Qt.BottomEdge | Qt.LeftEdge; cursorShape: Qt.SizeBDiagCursor; x: -grow; y: win.height - 12; width: 12 + grow; height: 12 + grow }
            Handle { edges: Qt.BottomEdge | Qt.RightEdge; cursorShape: Qt.SizeFDiagCursor; x: win.width - 12; y: win.height - 12; width: 12 + grow; height: 12 + grow }
        }

        // Clicking an inactive window activates it and lets the click through.
        MouseArea {
            anchors.fill: parent
            enabled: !win.active
            acceptedButtons: Qt.AllButtons
            onPressed: (m) => {
                Shell.activate(win)
                m.accepted = false
            }
        }
    }
}
