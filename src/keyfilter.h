// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QObject>
#include <QQmlEngine>

// Global shortcuts. Installed as an application-wide event filter so the shell
// sees key presses before they are forwarded to the focused Wayland client.
class KeyFilter : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Shortcuts)
    QML_SINGLETON
    Q_PROPERTY(bool locked READ locked WRITE setLocked NOTIFY lockedChanged)
    Q_PROPERTY(bool switching READ switching NOTIFY switchingChanged)

public:
    static KeyFilter *instance();
    static KeyFilter *create(QQmlEngine *, QJSEngine *);

    bool locked() const { return m_locked; }
    void setLocked(bool l);
    bool switching() const { return m_switching; }

    // Maps a key event to a shortcut name ("" if none). Exposed for tests.
    static QString shortcutFor(int key, Qt::KeyboardModifiers mods);

Q_SIGNALS:
    void lockedChanged();
    void switchingChanged();
    void shortcut(const QString &name);

public:
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    explicit KeyFilter(QObject *parent = nullptr);
    void setSwitching(bool s);
    bool m_locked = false;
    bool m_metaDown = false;
    bool m_metaUsed = false;
    bool m_switching = false;
};
