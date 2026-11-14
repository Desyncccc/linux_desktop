// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QHash>
#include <QString>
#include <QStringList>

// Parser for freedesktop.org .desktop files (Desktop Entry Specification 1.5).
// Kept free of QML/GUI dependencies so it can be unit tested in isolation.
class DesktopEntry
{
public:
    static DesktopEntry fromFile(const QString &path, const QString &desktopId = {});
    static DesktopEntry fromData(const QByteArray &data, const QString &desktopId = {});

    // Splits an Exec value into arguments following the spec's quoting rules
    // and expands field codes (%f %F %u %U %i %c %k %%).
    QStringList execArgs(const QStringList &files = {}) const;

    // Returns true if the entry should be listed for the given desktop name.
    bool isVisibleIn(const QString &desktop) const;

    bool isValid() const { return m_valid; }
    QString desktopId() const { return m_desktopId; }
    QString path() const { return m_path; }
    QString type() const { return value(QStringLiteral("Type")); }
    QString name() const { return localized(QStringLiteral("Name")); }
    QString genericName() const { return localized(QStringLiteral("GenericName")); }
    QString comment() const { return localized(QStringLiteral("Comment")); }
    QString icon() const { return value(QStringLiteral("Icon")); }
    QString exec() const { return value(QStringLiteral("Exec")); }
    QString tryExec() const { return value(QStringLiteral("TryExec")); }
    QString workingDirectory() const { return value(QStringLiteral("Path")); }
    QString startupWMClass() const { return value(QStringLiteral("StartupWMClass")); }
    QStringList categories() const { return list(QStringLiteral("Categories")); }
    QStringList keywords() const;
    QStringList onlyShowIn() const { return list(QStringLiteral("OnlyShowIn")); }
    QStringList notShowIn() const { return list(QStringLiteral("NotShowIn")); }
    bool noDisplay() const { return boolValue(QStringLiteral("NoDisplay")); }
    bool hidden() const { return boolValue(QStringLiteral("Hidden")); }
    bool terminal() const { return boolValue(QStringLiteral("Terminal")); }

    QString value(const QString &key, const QString &group = QStringLiteral("Desktop Entry")) const;
    QString localized(const QString &key) const;
    QStringList list(const QString &key) const;
    bool boolValue(const QString &key) const;

    // Locale used for localized keys, e.g. "de_DE". Defaults to the system locale.
    static void setLocaleOverride(const QString &locale);

    // Splits a ";"-separated list honouring "\;" escapes.
    static QStringList splitList(const QString &value);
    // Unescapes \s \n \t \r \\ in string values.
    static QString unescape(const QString &value);
    // Tokenizes an Exec line (no field code expansion).
    static QStringList tokenizeExec(const QString &exec, bool *ok = nullptr);

private:
    void parse(const QByteArray &data);

    bool m_valid = false;
    QString m_desktopId;
    QString m_path;
    QHash<QString, QHash<QString, QString>> m_groups;
};
