// SPDX-License-Identifier: GPL-3.0-or-later
#include "iconprovider.h"

#include <QDir>
#include <QFileInfo>
#include <QIcon>
#include <QUrl>

IconProvider::IconProvider()
    : QQuickImageProvider(QQuickImageProvider::Pixmap)
{
}

void IconProvider::setupTheme(const QString &preferred)
{
    QStringList paths = QIcon::themeSearchPaths();
    paths << QDir::homePath() + QStringLiteral("/.local/share/icons") << QStringLiteral("/usr/share/icons");
    paths << QDir::homePath() + QStringLiteral("/.local/share/flatpak/exports/share/icons")
          << QStringLiteral("/var/lib/flatpak/exports/share/icons");
    paths.removeDuplicates();
    QIcon::setThemeSearchPaths(paths);
    QIcon::setFallbackSearchPaths({QStringLiteral("/usr/share/pixmaps")});

    QStringList candidates;
    if (!preferred.isEmpty())
        candidates << preferred;
    candidates << QStringLiteral("Papirus") << QStringLiteral("breeze") << QStringLiteral("Adwaita")
               << QStringLiteral("elementary") << QStringLiteral("Humanity") << QStringLiteral("hicolor");
    for (const QString &theme : candidates) {
        for (const QString &base : paths) {
            if (QFileInfo::exists(base + QLatin1Char('/') + theme + QStringLiteral("/index.theme"))) {
                QIcon::setThemeName(theme);
                if (theme != QLatin1String("hicolor"))
                    QIcon::setFallbackThemeName(QStringLiteral("hicolor"));
                return;
            }
        }
    }
}

QPixmap IconProvider::requestPixmap(const QString &id, QSize *size, const QSize &requestedSize)
{
    const int w = requestedSize.width() > 0 ? requestedSize.width() : 48;
    const int h = requestedSize.height() > 0 ? requestedSize.height() : w;
    const QSize target(w, h);
    if (size)
        *size = target;

    const QStringList names = QUrl::fromPercentEncoding(id.toUtf8()).split(QLatin1Char('|'), Qt::SkipEmptyParts);
    for (const QString &raw : names) {
        QString name = raw;
        if (name.startsWith(QLatin1String("file://")))
            name = QUrl(name).toLocalFile();
        QIcon icon;
        if (name.startsWith(QLatin1Char('/'))) {
            if (QFileInfo::exists(name))
                icon = QIcon(name);
        } else if (name.startsWith(QLatin1Char(':'))) {
            icon = QIcon(name);
        } else {
            icon = QIcon::fromTheme(name);
            if (icon.isNull() && name.contains(QLatin1Char('.'))) {
                // Some entries specify "foo.png" relative names.
                icon = QIcon::fromTheme(QFileInfo(name).completeBaseName());
            }
        }
        if (!icon.isNull()) {
            const QPixmap pm = icon.pixmap(target);
            if (!pm.isNull())
                return pm;
        }
    }
    QPixmap pm(QStringLiteral(":/qt/qml/Vitrum/icons/app-generic.svg"));
    if (!pm.isNull())
        return pm.scaled(target, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    pm = QPixmap(target);
    pm.fill(Qt::transparent);
    return pm;
}
