// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QColor>
#include <QPointF>
#include <QObject>
#include <QQmlEngine>
#include <QSettings>
#include <QStringList>

// Persistent shell preferences (~/.config/Vitrum/vitrum.conf).
class Prefs : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

#define VITRUM_PREF(type, name, setter, key, def)                                                  \
    Q_PROPERTY(type name READ name WRITE setter NOTIFY name##Changed)                              \
public:                                                                                            \
    type name() const { return m_settings.value(QStringLiteral(key), def).value<type>(); }        \
    void setter(const type &v)                                                                     \
    {                                                                                              \
        if (v == name())                                                                           \
            return;                                                                                \
        m_settings.setValue(QStringLiteral(key), QVariant::fromValue(v));                          \
        Q_EMIT name##Changed();                                                                    \
    }                                                                                              \
    Q_SIGNAL void name##Changed();                                                                 \
private:

    VITRUM_PREF(QString, theme, setTheme, "appearance/theme", QStringLiteral("aero"))
    VITRUM_PREF(QColor, accentColor, setAccentColor, "appearance/accentColor", QColor(QStringLiteral("#3a7bd5")))
    VITRUM_PREF(qreal, colorIntensity, setColorIntensity, "appearance/colorIntensity", 0.45)
    VITRUM_PREF(bool, transparency, setTransparency, "appearance/transparency", true)
    VITRUM_PREF(QString, wallpaper, setWallpaper, "appearance/wallpaper", QStringLiteral("builtin:aurora"))
    VITRUM_PREF(QString, iconTheme, setIconTheme, "appearance/iconTheme", QString())
    VITRUM_PREF(bool, animations, setAnimations, "appearance/animations", true)
    VITRUM_PREF(bool, taskbarCentered, setTaskbarCentered, "taskbar/centered", false)
    VITRUM_PREF(bool, smallTaskbarIcons, setSmallTaskbarIcons, "taskbar/smallIcons", false)
    VITRUM_PREF(bool, combineButtons, setCombineButtons, "taskbar/combine", true)
    VITRUM_PREF(QStringList, pinnedApps, setPinnedApps, "taskbar/pinned", QStringList())
    VITRUM_PREF(QStringList, startPinned, setStartPinned, "start/pinned", QStringList())
    VITRUM_PREF(bool, clock24h, setClock24h, "clock/use24h", true)
    VITRUM_PREF(bool, showSeconds, setShowSeconds, "clock/showSeconds", false)
    VITRUM_PREF(bool, doNotDisturb, setDoNotDisturb, "notifications/doNotDisturb", false)
    VITRUM_PREF(bool, nightLight, setNightLight, "display/nightLight", false)
    VITRUM_PREF(qreal, nightLightStrength, setNightLightStrength, "display/nightLightStrength", 0.35)
    VITRUM_PREF(bool, showDesktopIcons, setShowDesktopIcons, "desktop/showIcons", true)
    VITRUM_PREF(QString, keyboardLayout, setKeyboardLayout, "input/keyboardLayout", QString())
    VITRUM_PREF(bool, firstRunDone, setFirstRunDone, "general/firstRunDone", false)
    VITRUM_PREF(bool, welcomeShown, setWelcomeShown, "general/welcomeShown", false)

#undef VITRUM_PREF

public:
    static Prefs *instance();
    static Prefs *create(QQmlEngine *, QJSEngine *);

    Q_INVOKABLE bool isPinned(const QString &desktopId) const;
    Q_INVOKABLE void pin(const QString &desktopId);
    Q_INVOKABLE void unpin(const QString &desktopId);
    Q_INVOKABLE void movePinned(const QString &desktopId, int newIndex);
    Q_INVOKABLE bool isStartPinned(const QString &desktopId) const;
    Q_INVOKABLE void pinToStart(const QString &desktopId);
    Q_INVOKABLE void unpinFromStart(const QString &desktopId);
    Q_INVOKABLE void recordLaunch(const QString &desktopId);
    Q_INVOKABLE QStringList frequentApps(int count) const;
    Q_INVOKABLE void resetToDefaults();
    // Populates default pins with whatever common apps are installed.
    void seedDefaults();

    // Desktop icon positions, keyed by file path.
    Q_INVOKABLE QPointF iconPosition(const QString &key) const;
    Q_INVOKABLE void setIconPosition(const QString &key, const QPointF &pos);

Q_SIGNALS:
    void launchCountsChanged();

private:
    explicit Prefs(QObject *parent = nullptr);
    QSettings m_settings;
};
