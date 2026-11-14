// SPDX-License-Identifier: GPL-3.0-or-later
#include "keyfilter.h"

#include <QKeyEvent>
#include <QWindow>

static KeyFilter *s_keys = nullptr;

KeyFilter::KeyFilter(QObject *parent)
    : QObject(parent)
{
}

KeyFilter *KeyFilter::instance()
{
    if (!s_keys)
        s_keys = new KeyFilter;
    return s_keys;
}

KeyFilter *KeyFilter::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

void KeyFilter::setLocked(bool l)
{
    if (l == m_locked)
        return;
    m_locked = l;
    setSwitching(false);
    Q_EMIT lockedChanged();
}

void KeyFilter::setSwitching(bool s)
{
    if (s == m_switching)
        return;
    m_switching = s;
    Q_EMIT switchingChanged();
}

static bool isMetaKey(int key)
{
    return key == Qt::Key_Super_L || key == Qt::Key_Super_R || key == Qt::Key_Meta;
}

QString KeyFilter::shortcutFor(int key, Qt::KeyboardModifiers mods)
{
    const bool meta = mods & Qt::MetaModifier;
    const bool alt = mods & Qt::AltModifier;
    const bool ctrl = mods & Qt::ControlModifier;
    const bool shift = mods & Qt::ShiftModifier;

    switch (key) {
    case Qt::Key_VolumeUp: return QStringLiteral("volumeUp");
    case Qt::Key_VolumeDown: return QStringLiteral("volumeDown");
    case Qt::Key_VolumeMute: return QStringLiteral("volumeMute");
    case Qt::Key_MonBrightnessUp: return QStringLiteral("brightnessUp");
    case Qt::Key_MonBrightnessDown: return QStringLiteral("brightnessDown");
    case Qt::Key_Print: return alt ? QStringLiteral("screenshotWindow") : QStringLiteral("screenshot");
    default: break;
    }

    if (meta && !ctrl && !alt) {
        if (key >= Qt::Key_1 && key <= Qt::Key_9)
            return QStringLiteral("taskbar:%1").arg(key - Qt::Key_1);
        switch (key) {
        case Qt::Key_D: return QStringLiteral("showDesktop");
        case Qt::Key_M: return QStringLiteral("minimizeAll");
        case Qt::Key_E: return QStringLiteral("explorer");
        case Qt::Key_R: return QStringLiteral("run");
        case Qt::Key_L: return QStringLiteral("lock");
        case Qt::Key_A: return QStringLiteral("actionCenter");
        case Qt::Key_N: return QStringLiteral("actionCenter");
        case Qt::Key_I: return QStringLiteral("settings");
        case Qt::Key_S: return QStringLiteral("search");
        case Qt::Key_Q: return QStringLiteral("search");
        case Qt::Key_X: return QStringLiteral("quickLink");
        case Qt::Key_Z: return QStringLiteral("snapLayouts");
        case Qt::Key_Pause: return QStringLiteral("about");
        case Qt::Key_Tab: return shift ? QStringLiteral("switchPrev") : QStringLiteral("switchNext");
        case Qt::Key_Left: return QStringLiteral("snapLeft");
        case Qt::Key_Right: return QStringLiteral("snapRight");
        case Qt::Key_Up: return QStringLiteral("maximize");
        case Qt::Key_Down: return QStringLiteral("restoreOrMinimize");
        case Qt::Key_Home: return QStringLiteral("minimizeOthers");
        default: break;
        }
    }
    if (alt && !ctrl && !meta) {
        if (key == Qt::Key_Tab || key == Qt::Key_Backtab)
            return (shift || key == Qt::Key_Backtab) ? QStringLiteral("switchPrev") : QStringLiteral("switchNext");
        if (key == Qt::Key_F4)
            return QStringLiteral("close");
        if (key == Qt::Key_F2)
            return QStringLiteral("run");
    }
    if (ctrl && shift && !alt && key == Qt::Key_Escape)
        return QStringLiteral("taskManager");
    if (ctrl && alt && (key == Qt::Key_Delete || key == Qt::Key_Backspace))
        return QStringLiteral("secureAttention");
    if (ctrl && alt && key == Qt::Key_T)
        return QStringLiteral("terminal");
    if (ctrl && key == Qt::Key_Escape && !shift && !alt)
        return QStringLiteral("start");
    return {};
}

bool KeyFilter::eventFilter(QObject *watched, QEvent *event)
{
    // Each key event passes through the QWindow first, then to Quick items:
    // only act on the window-level delivery.
    if (event->type() != QEvent::KeyPress && event->type() != QEvent::KeyRelease)
        return false;
    if (!qobject_cast<QWindow *>(watched))
        return false;
    auto *ke = static_cast<QKeyEvent *>(event);
    const int key = ke->key();

    if (m_locked) {
        m_metaDown = false;
        return false;
    }

    if (event->type() == QEvent::KeyPress) {
        if (isMetaKey(key)) {
            if (!ke->isAutoRepeat()) {
                m_metaDown = true;
                m_metaUsed = false;
            }
            return false;
        }
        if (m_metaDown)
            m_metaUsed = true;

        if (m_switching && key == Qt::Key_Escape) {
            setSwitching(false);
            Q_EMIT shortcut(QStringLiteral("switchCancel"));
            return true;
        }
        const QString name = shortcutFor(key, ke->modifiers());
        if (name.isEmpty())
            return false;
        if (name == QLatin1String("switchNext") || name == QLatin1String("switchPrev"))
            setSwitching(true);
        Q_EMIT shortcut(name);
        return true;
    }

    // KeyRelease
    if (isMetaKey(key)) {
        const bool tap = m_metaDown && !m_metaUsed && !ke->isAutoRepeat();
        m_metaDown = false;
        if (m_switching) {
            setSwitching(false);
            Q_EMIT shortcut(QStringLiteral("switchCommit"));
        }
        if (tap) {
            Q_EMIT shortcut(QStringLiteral("start"));
            return true;
        }
        return false;
    }
    if (m_switching && (key == Qt::Key_Alt || key == Qt::Key_AltGr || !(ke->modifiers() & (Qt::AltModifier | Qt::MetaModifier)))) {
        if (key == Qt::Key_Alt || key == Qt::Key_AltGr) {
            setSwitching(false);
            Q_EMIT shortcut(QStringLiteral("switchCommit"));
        }
    }
    return false;
}
