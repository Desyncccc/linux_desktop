// SPDX-License-Identifier: GPL-3.0-or-later
#include "prefs.h"
#include "appmodel.h"

#include <algorithm>

static Prefs *s_prefs = nullptr;

Prefs::Prefs(QObject *parent)
    : QObject(parent)
    , m_settings(QSettings::IniFormat, QSettings::UserScope, QStringLiteral("Vitrum"), QStringLiteral("vitrum"))
{
}

Prefs *Prefs::instance()
{
    if (!s_prefs)
        s_prefs = new Prefs;
    return s_prefs;
}

Prefs *Prefs::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

bool Prefs::isPinned(const QString &id) const { return pinnedApps().contains(id); }

void Prefs::pin(const QString &id)
{
    QStringList l = pinnedApps();
    if (!id.isEmpty() && !l.contains(id)) {
        l << id;
        setPinnedApps(l);
    }
}

void Prefs::unpin(const QString &id)
{
    QStringList l = pinnedApps();
    if (l.removeAll(id))
        setPinnedApps(l);
}

void Prefs::movePinned(const QString &id, int newIndex)
{
    QStringList l = pinnedApps();
    const int from = int(l.indexOf(id));
    if (from < 0)
        return;
    newIndex = std::clamp(newIndex, 0, int(l.size()) - 1);
    if (from == newIndex)
        return;
    l.move(from, newIndex);
    setPinnedApps(l);
}

bool Prefs::isStartPinned(const QString &id) const { return startPinned().contains(id); }

void Prefs::pinToStart(const QString &id)
{
    QStringList l = startPinned();
    if (!id.isEmpty() && !l.contains(id)) {
        l << id;
        setStartPinned(l);
    }
}

void Prefs::unpinFromStart(const QString &id)
{
    QStringList l = startPinned();
    if (l.removeAll(id))
        setStartPinned(l);
}

void Prefs::recordLaunch(const QString &id)
{
    const QString key = QStringLiteral("usage/") + QString(id).replace(QLatin1Char('/'), QLatin1Char('_'));
    m_settings.setValue(key, m_settings.value(key, 0).toInt() + 1);
    Q_EMIT launchCountsChanged();
}

QStringList Prefs::frequentApps(int count) const
{
    QList<QPair<int, QString>> usage;
    auto *self = const_cast<QSettings *>(&m_settings);
    self->beginGroup(QStringLiteral("usage"));
    const QStringList keys = self->childKeys();
    for (const QString &k : keys)
        usage.append({self->value(k).toInt(), k});
    self->endGroup();
    std::sort(usage.begin(), usage.end(), [](auto a, auto b) { return a.first > b.first; });
    QStringList out;
    for (const auto &u : usage) {
        if (out.size() >= count)
            break;
        if (AppModel::instance()->entry(u.second))
            out << u.second;
    }
    return out;
}

QPointF Prefs::iconPosition(const QString &key) const
{
    return m_settings.value(QStringLiteral("desktopIcons/") + QString::fromLatin1(key.toUtf8().toBase64(QByteArray::Base64UrlEncoding)),
                            QPointF(-1, -1)).toPointF();
}

void Prefs::setIconPosition(const QString &key, const QPointF &pos)
{
    m_settings.setValue(QStringLiteral("desktopIcons/") + QString::fromLatin1(key.toUtf8().toBase64(QByteArray::Base64UrlEncoding)), pos);
}

void Prefs::resetToDefaults()
{
    const QStringList keep = {QStringLiteral("taskbar/pinned"), QStringLiteral("start/pinned"), QStringLiteral("general/firstRunDone")};
    for (const QString &k : m_settings.allKeys())
        if (!keep.contains(k) && !k.startsWith(QLatin1String("usage/")) && !k.startsWith(QLatin1String("desktopIcons/")))
            m_settings.remove(k);
    Q_EMIT themeChanged(); Q_EMIT accentColorChanged(); Q_EMIT colorIntensityChanged(); Q_EMIT transparencyChanged();
    Q_EMIT wallpaperChanged(); Q_EMIT animationsChanged(); Q_EMIT taskbarCenteredChanged();
    Q_EMIT smallTaskbarIconsChanged(); Q_EMIT combineButtonsChanged(); Q_EMIT clock24hChanged();
    Q_EMIT showSecondsChanged(); Q_EMIT nightLightChanged(); Q_EMIT nightLightStrengthChanged();
    Q_EMIT showDesktopIconsChanged(); Q_EMIT iconThemeChanged();
}

void Prefs::seedDefaults()
{
    if (firstRunDone())
        return;
    AppModel *apps = AppModel::instance();
    auto firstAvailable = [apps](const QStringList &ids) -> QString {
        for (const QString &id : ids)
            if (apps->entry(id))
                return id;
        return {};
    };
    const QList<QStringList> taskbarGroups = {
        {QStringLiteral("firefox.desktop"), QStringLiteral("firefox_firefox.desktop"), QStringLiteral("org.mozilla.firefox.desktop"),
         QStringLiteral("chromium.desktop"), QStringLiteral("chromium_chromium.desktop"), QStringLiteral("google-chrome.desktop"),
         QStringLiteral("org.gnome.Epiphany.desktop"), QStringLiteral("org.kde.falkon.desktop")},
        {QStringLiteral("org.kde.dolphin.desktop"), QStringLiteral("org.gnome.Nautilus.desktop"), QStringLiteral("nemo.desktop"),
         QStringLiteral("thunar.desktop"), QStringLiteral("pcmanfm-qt.desktop")},
        {QStringLiteral("foot.desktop"), QStringLiteral("org.kde.konsole.desktop"), QStringLiteral("org.gnome.Terminal.desktop"),
         QStringLiteral("org.gnome.Console.desktop"), QStringLiteral("kitty.desktop"), QStringLiteral("Alacritty.desktop"),
         QStringLiteral("xfce4-terminal.desktop"), QStringLiteral("weston-terminal.desktop")},
    };
    QStringList pins;
    for (const auto &g : taskbarGroups) {
        const QString id = firstAvailable(g);
        if (!id.isEmpty())
            pins << id;
    }
    setPinnedApps(pins);

    const QList<QStringList> startGroups = {
        {QStringLiteral("org.gnome.TextEditor.desktop"), QStringLiteral("org.kde.kate.desktop"), QStringLiteral("org.gnome.gedit.desktop"),
         QStringLiteral("mousepad.desktop"), QStringLiteral("org.kde.kwrite.desktop")},
        {QStringLiteral("org.gnome.Calculator.desktop"), QStringLiteral("org.kde.kcalc.desktop"), QStringLiteral("galculator.desktop")},
        {QStringLiteral("libreoffice-writer.desktop")},
        {QStringLiteral("vlc.desktop"), QStringLiteral("org.gnome.Totem.desktop"), QStringLiteral("mpv.desktop")},
    };
    QStringList start = pins;
    for (const auto &g : startGroups) {
        const QString id = firstAvailable(g);
        if (!id.isEmpty())
            start << id;
    }
    setStartPinned(start);
    setFirstRunDone(true);
}
