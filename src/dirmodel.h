// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QDirIterator>
#include <QFileSystemWatcher>
#include <QQmlEngine>
#include <QTimer>
#include <memory>

// Folder contents for Explorer: sorting, filtering, live refresh and a
// recursive search that fills the same model. System folders at the root of
// the disk are hidden like protected operating-system files.
class DirModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(bool showHidden READ showHidden WRITE setShowHidden NOTIFY showHiddenChanged)
    Q_PROPERTY(QString sortField READ sortField WRITE setSortField NOTIFY sortChanged)
    Q_PROPERTY(bool sortDescending READ sortDescending WRITE setSortDescending NOTIFY sortChanged)
    Q_PROPERTY(QString searchText READ searchText WRITE setSearchText NOTIFY searchTextChanged)
    Q_PROPERTY(bool searching READ searching NOTIFY searchingChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(qint64 totalSize READ totalSize NOTIFY countChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        FileNameRole,
        PathRole,
        IsDirRole,
        SizeRole,
        SizeTextRole,
        ModifiedRole,
        ModifiedTextRole,
        TypeRole,
        IconRole,
        IsImageRole,
        HiddenRole,
        LocationRole,
    };

    explicit DirModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    QString path() const { return m_path; }
    void setPath(const QString &p);
    bool showHidden() const { return m_showHidden; }
    void setShowHidden(bool s);
    QString sortField() const { return m_sortField; }
    void setSortField(const QString &f);
    bool sortDescending() const { return m_desc; }
    void setSortDescending(bool d);
    QString searchText() const { return m_search; }
    void setSearchText(const QString &t);
    bool searching() const { return m_iter != nullptr; }
    int count() const { return int(m_items.size()); }
    qint64 totalSize() const;

    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE int indexOf(const QString &path) const;
    Q_INVOKABLE QString pathAt(int row) const;
    Q_INVOKABLE void refresh();
    // Names hidden at the root of the disk ("protected operating system files").
    static bool isSystemEntry(const QString &dir, const QString &name);

Q_SIGNALS:
    void pathChanged();
    void showHiddenChanged();
    void sortChanged();
    void searchTextChanged();
    void searchingChanged();
    void countChanged();

private:
    struct Item {
        QString name, fileName, path, type, icon, location;
        bool isDir = false, hidden = false, image = false;
        qint64 size = 0;
        QDateTime modified;
    };
    Item makeItem(const QFileInfo &fi) const;
    void reload();
    void sortItems(QList<Item> &items) const;
    void stopSearch();
    void searchStep();

    QString m_path;
    bool m_showHidden = false;
    QString m_sortField = QStringLiteral("name");
    bool m_desc = false;
    QString m_search;
    QList<Item> m_items;
    QFileSystemWatcher m_watcher;
    QTimer m_reloadTimer;
    std::unique_ptr<QDirIterator> m_iter;
    QTimer m_searchTimer;
};
