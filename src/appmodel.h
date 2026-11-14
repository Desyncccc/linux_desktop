// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include "desktopentry.h"

#include <QAbstractListModel>
#include <QFileSystemWatcher>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantMap>

// Lists installed applications (.desktop files on the XDG data path).
class AppModel : public QAbstractListModel
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Apps)
    QML_SINGLETON
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    enum Roles {
        DesktopIdRole = Qt::UserRole + 1,
        NameRole,
        GenericNameRole,
        CommentRole,
        IconRole,
        CategoryRole,
        KeywordsRole,
    };
    Q_ENUM(Roles)

    explicit AppModel(QObject *parent = nullptr);
    static AppModel *instance();
    static AppModel *create(QQmlEngine *, QJSEngine *);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return int(m_entries.size()); }

    Q_INVOKABLE QVariantMap get(const QString &desktopId) const;
    Q_INVOKABLE QVariantList search(const QString &query, int limit = 12) const;
    Q_INVOKABLE QVariantList all() const;
    Q_INVOKABLE QVariantList categoryGroups() const;
    Q_INVOKABLE QVariantList appsForIds(const QStringList &ids) const;
    // Maps a Wayland app_id (or X11 WM_CLASS) to a desktop id, "" if unknown.
    Q_INVOKABLE QString idForAppId(const QString &appId) const;
    Q_INVOKABLE bool launch(const QString &desktopId, const QStringList &files = {});
    Q_INVOKABLE void reload();
    // Makes a pinnable entry for a program file (.exe, .jar, script, binary,
    // .desktop). Returns its desktop id, or "" if the file isn't a program.
    Q_INVOKABLE QString ensureEntryForFile(const QString &path);
    Q_INVOKABLE bool isProgramFile(const QString &path) const;

    const DesktopEntry *entry(const QString &desktopId) const;
    static QStringList applicationDirs();
    static bool isRuntimePlumbing(const DesktopEntry &e);
    static QString mainCategory(const QStringList &categories);
    // Returns XDG autostart entries that should run in this session.
    static QList<DesktopEntry> autostartEntries();

Q_SIGNALS:
    void countChanged();
    void launched(const QString &desktopId);

private:
    QVariantMap toMap(const DesktopEntry &e) const;
    QList<DesktopEntry> m_entries;
    QHash<QString, int> m_index;
    QFileSystemWatcher m_watcher;
    QTimer m_reloadTimer;
};
