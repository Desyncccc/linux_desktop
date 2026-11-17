// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QList>
#include <QObject>
#include <QPointer>
#include <QQmlEngine>
#include <QWaylandSeat>
#include <QWaylandSurface>
#include <QWaylandXdgPopup>
#include <QWaylandXdgSurface>

class QWaylandClient;

// Qt's compositor doesn't implement xdg_popup.grab, so menus opened by clients
// never learn that the user clicked elsewhere. Browsers (Firefox) then keep
// their menu "open", swallow input and look frozen. This emulates the grab:
// a press anywhere outside the popup's own client, or focus moving to another
// client, dismisses the client's popups with popup_done.
class PopupGrab : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QWaylandSeat *seat READ seat WRITE setSeat NOTIFY seatChanged)

public:
    static PopupGrab *instance();
    static PopupGrab *create(QQmlEngine *, QJSEngine *);

    QWaylandSeat *seat() const { return m_seat; }
    void setSeat(QWaylandSeat *seat);

    // Called from QML when XdgShell reports a new popup.
    Q_INVOKABLE void track(QObject *popup);
    // Dismisses every popup that doesn't belong to |keep| (null: dismiss all).
    void dismissExcept(QWaylandClient *keep);
    Q_INVOKABLE void dismissAll() { dismissExcept(nullptr); }

    bool eventFilter(QObject *watched, QEvent *event) override;

Q_SIGNALS:
    void seatChanged();
    // A popup closed and left no surface with keyboard focus.
    void keyboardFocusLost();

private:
    explicit PopupGrab(QObject *parent = nullptr);
    QPointer<QWaylandSeat> m_seat;
    // Qt doesn't implement xdg_popup.destroy, so a popup object can outlive
    // its xdg_surface: hold guarded pointers to all three and only touch the
    // popup while its surfaces are alive.
    struct Entry {
        QPointer<QWaylandXdgPopup> popup;
        QPointer<QWaylandXdgSurface> xdgSurface;
        QPointer<QWaylandSurface> surface;
        bool alive() const { return popup && xdgSurface && surface; }
    };
    void prune();
    QList<Entry> m_popups;
    bool m_delivering = false;
};
