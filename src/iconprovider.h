// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QQuickImageProvider>

// image://icon/<name>[|<fallback>...]  — freedesktop icon theme lookup.
class IconProvider : public QQuickImageProvider
{
public:
    IconProvider();
    QPixmap requestPixmap(const QString &id, QSize *size, const QSize &requestedSize) override;
    static void setupTheme(const QString &preferred);
};
