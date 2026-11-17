// SPDX-License-Identifier: GPL-3.0-or-later
#include "popupgrab.h"

#include <QEvent>
#include <algorithm>
#include <QGuiApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QWaylandClient>
#include <QWaylandQuickItem>
#include <QWaylandSeat>
#include <QWaylandSurface>
#include <QWaylandView>
#include <QWaylandXdgPopup>
#include <QWaylandXdgSurface>

static PopupGrab *s_grab = nullptr;

PopupGrab::PopupGrab(QObject *parent)
    : QObject(parent)
{
}

PopupGrab *PopupGrab::instance()
{
    if (!s_grab)
        s_grab = new PopupGrab;
    return s_grab;
}

PopupGrab *PopupGrab::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

void PopupGrab::setSeat(QWaylandSeat *seat)
{
    if (m_seat == seat)
        return;
    if (m_seat)
        disconnect(m_seat, nullptr, this, nullptr);
    m_seat = seat;
    if (m_seat) {
        // Keyboard focus moving to another client (Alt+Tab, clicking another
        // window, the shell taking focus) ends the grab.
        connect(m_seat, &QWaylandSeat::keyboardFocusChanged, this, [this](QWaylandSurface *now, QWaylandSurface *) {
            dismissExcept(now ? now->client() : nullptr);
        });
    }
    Q_EMIT seatChanged();
}

void PopupGrab::track(QObject *object)
{
    auto *popup = qobject_cast<QWaylandXdgPopup *>(object);
    if (!popup || !popup->xdgSurface() || !popup->xdgSurface()->surface())
        return;
    Entry e{popup, popup->xdgSurface(), popup->xdgSurface()->surface()};
    // Forget the popup as soon as the client tears its surface down.
    connect(e.surface, &QWaylandSurface::surfaceDestroyed, this, [this] { prune(); }, Qt::QueuedConnection);
    connect(e.xdgSurface, &QObject::destroyed, this, [this] { prune(); }, Qt::QueuedConnection);
    prune();
    m_popups.append(e);
    qGuiApp->installEventFilter(this);
}

void PopupGrab::prune()
{
    const auto before = m_popups.size();
    m_popups.erase(std::remove_if(m_popups.begin(), m_popups.end(), [](const Entry &e) { return !e.alive(); }),
                   m_popups.end());
    // A closed popup that held the keyboard leaves nothing focused: hand the
    // keyboard back to the window the menu belonged to.
    if (m_popups.size() != before && m_seat) {
        QWaylandSurface *focus = m_seat->keyboardFocus();
        if (!focus || !focus->hasContent())
            Q_EMIT keyboardFocusLost();
    }
    if (m_popups.isEmpty())
        qGuiApp->removeEventFilter(this);
}

void PopupGrab::dismissExcept(QWaylandClient *keep)
{
    prune();
    // Close the newest first: nested menus are dismissed child before parent.
    QList<Entry> remaining;
    for (int i = int(m_popups.size()) - 1; i >= 0; --i) {
        const Entry &e = m_popups.at(i);
        if (keep && e.surface->client() == keep) {
            remaining.prepend(e);
            continue;
        }
        e.popup->sendPopupDone();
    }
    m_popups = remaining;
    if (m_popups.isEmpty())
        qGuiApp->removeEventFilter(this);
}

bool PopupGrab::eventFilter(QObject *watched, QEvent *event)
{
    const QEvent::Type t = event->type();
    if (m_delivering || (t != QEvent::MouseButtonPress && t != QEvent::TouchBegin))
        return false;
    auto *window = qobject_cast<QQuickWindow *>(watched);
    if (!window)
        return false;
    prune();
    if (m_popups.isEmpty())
        return false;
    // Deliver the press now, then see which item took it: a client surface
    // (whose?) or part of the shell. Items that only peek at a press and pass
    // it on (e.g. click-to-activate areas) don't count.
    m_delivering = true;
    QCoreApplication::sendEvent(window, event);
    m_delivering = false;
    auto *pe = static_cast<QPointerEvent *>(event);
    QObject *grabber = pe->pointCount() > 0 ? pe->exclusiveGrabber(pe->point(0)) : nullptr;
    QWaylandClient *client = nullptr;
    if (auto *item = qobject_cast<QWaylandQuickItem *>(grabber))
        client = item->surface() ? item->surface()->client() : nullptr;
    dismissExcept(client);
    return true;
}
