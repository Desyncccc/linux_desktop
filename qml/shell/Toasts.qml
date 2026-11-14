import QtQuick
import Qt5Compat.GraphicalEffects
import Vitrum
import Vitrum.Core

// Notification toasts above the notification area.
Item {
    id: toasts
    width: 364
    height: Shell.screenHeight - Theme.taskbarHeight
    x: Shell.screenWidth - width - 10

    ListModel { id: active }

    function push(id, timeout) {
        if (Prefs.doNotDisturb || Shell.locked)
            return
        const n = Notifications.get(id)
        if (!n.notificationId)
            return
        for (let i = 0; i < active.count; ++i)
            if (active.get(i).nid === id) {
                active.remove(i)
                break
            }
        active.insert(0, { nid: id, timeout: timeout })
        while (active.count > 3)
            active.remove(active.count - 1)
    }
    function drop(id) {
        for (let i = 0; i < active.count; ++i)
            if (active.get(i).nid === id) {
                active.remove(i)
                return
            }
    }

    Connections {
        target: Notifications
        function onNotificationAdded(id, timeout) { toasts.push(id, timeout) }
        function onNotificationRemoved(id) { toasts.drop(id) }
    }
    Connections {
        target: Shell
        function onNotify(summary, body, icon) { Notifications.post(summary, body, icon) }
    }

    ListView {
        id: view
        anchors.fill: parent
        anchors.bottomMargin: 10
        verticalLayoutDirection: ListView.BottomToTop
        spacing: 8
        interactive: false
        model: active
        add: Transition {
            NumberAnimation { property: "x"; from: 380; to: 0; duration: Theme.anim(220); easing.type: Easing.OutCubic }
        }
        remove: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.anim(160) }
        }
        displaced: Transition { NumberAnimation { property: "y"; duration: Theme.anim(160) } }
        delegate: Item {
            id: toast
            required property int nid
            required property int timeout
            required property int index
            readonly property var n: Notifications.get(nid)
            width: view.width
            height: card.height + 4

            RectangularGlow {
                anchors.fill: bgPanel
                glowRadius: 8; spread: 0.1; cornerRadius: 12
                color: "#70000000"
            }
            GlassPanel {
                id: bgPanel
                anchors.fill: card
                tracking: toast
                radius: 5
                intensity: Theme.transparency ? Math.min(0.92, Theme.intensity + 0.3) : 0.96
                tint: Qt.darker(Theme.accent, 2.0)
            }
            NotificationCard {
                id: card
                width: parent.width
                toast: true
                notificationId: toast.nid
                appName: toast.n.appName || ""
                appIcon: toast.n.appIcon || ""
                summary: toast.n.summary || ""
                body: toast.n.body || ""
                actions: toast.n.actions || []
                image: toast.n.image || ""
                time: toast.n.time || null
                onDismissed: Notifications.dismiss(toast.nid)
                onActionClicked: (key) => Notifications.invokeAction(toast.nid, key)
                onClicked: { toasts.drop(toast.nid); Shell.toggleActionCenter() }
            }
            Timer {
                interval: toast.timeout > 0 ? toast.timeout : 6000
                running: toast.timeout !== 0
                onTriggered: { Notifications.expire(toast.nid); toasts.drop(toast.nid) }
            }
        }
    }
}
