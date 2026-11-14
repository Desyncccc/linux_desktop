import QtQuick
import QtQuick.Window
import QtWayland.Compositor as WL
import QtWayland.Compositor.XdgShell as Xdg
import Vitrum
import Vitrum.Core

// Vitrum: a Wayland compositor whose output window hosts the whole shell.
WL.WaylandCompositor {
    id: comp
    socketName: Launcher.socketName

    WL.WaylandOutput {
        id: output
        compositor: comp
        sizeFollowsWindow: true
        window: Window {
            id: screenWindow
            width: Session.windowed ? Session.windowSize.width : Screen.width
            height: Session.windowed ? Session.windowSize.height : Screen.height
            visibility: Session.windowed ? Window.Windowed : Window.FullScreen
            visible: true
            title: "Vitrum"
            color: "black"

            WL.WaylandMouseTracker {
                id: tracker
                anchors.fill: parent
                windowSystemCursorEnabled: true

                ShellScreen {
                    id: shellScreen
                    anchors.fill: parent
                    compositor: comp
                    window: screenWindow
                }

                WL.WaylandCursorItem {
                    id: clientCursor
                    inputEventsEnabled: false
                    x: tracker.mouseX
                    y: tracker.mouseY
                    z: 100000
                    seat: comp.defaultSeat
                    visible: Shell.pointerOnClient && tracker.containsMouse && surface !== null
                }
            }
        }
    }

    Xdg.XdgShell {
        onToplevelCreated: (toplevel, xdgSurface) => shellScreen.createClientWindow(xdgSurface)
    }
    Xdg.XdgDecorationManagerV1 {
        preferredMode: Xdg.XdgToplevel.ServerSideDecoration
    }

    Connections {
        target: comp.defaultSeat
        function onKeyboardFocusChanged(newFocus, oldFocus) {
            const w = Shell.windowForSurface(newFocus)
            if (w && w !== Shell.activeWindow && !w.closing)
                Shell.activate(w)
        }
        function onMouseFocusChanged(newFocus, oldFocus) {
            Shell.pointerOnClient = newFocus !== null
        }
    }

    Component.onCompleted: {
        const layout = Prefs.keyboardLayout.length > 0 ? Prefs.keyboardLayout : Session.env("XKB_DEFAULT_LAYOUT")
        if (layout.length > 0 && comp.defaultSeat)
            comp.defaultSeat.keymap.layout = layout
    }
}
