// SPDX-License-Identifier: GPL-3.0-or-later
#include "dirmodel.h"
#include "files.h"

#include <QCollator>
#include <QDir>
#include <QFileInfo>
#include <QLocale>
#include <QMimeDatabase>
#include <algorithm>

DirModel::DirModel(QObject *parent)
    : QAbstractListModel(parent)
{
    m_reloadTimer.setSingleShot(true);
    m_reloadTimer.setInterval(250);
    connect(&m_reloadTimer, &QTimer::timeout, this, &DirModel::reload);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] {
        if (m_search.isEmpty())
            m_reloadTimer.start();
    });
    m_searchTimer.setInterval(0);
    connect(&m_searchTimer, &QTimer::timeout, this, &DirModel::searchStep);
}

int DirModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QHash<int, QByteArray> DirModel::roleNames() const
{
    return {
        {NameRole, "name"}, {FileNameRole, "fileName"}, {PathRole, "filePath"}, {IsDirRole, "isDir"},
        {SizeRole, "size"}, {SizeTextRole, "sizeText"}, {ModifiedRole, "modified"},
        {ModifiedTextRole, "modifiedText"}, {TypeRole, "type"}, {IconRole, "icon"},
        {IsImageRole, "isImage"}, {HiddenRole, "hidden"}, {LocationRole, "location"},
    };
}

static QString sizeText(qint64 bytes)
{
    // Explorer shows sizes in whole KB.
    const qint64 kb = (bytes + 1023) / 1024;
    return QLocale().toString(kb) + QStringLiteral(" KB");
}

QVariant DirModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.size())
        return {};
    const Item &it = m_items.at(index.row());
    switch (role) {
    case Qt::DisplayRole:
    case NameRole: return it.name;
    case FileNameRole: return it.fileName;
    case PathRole: return it.path;
    case IsDirRole: return it.isDir;
    case SizeRole: return it.size;
    case SizeTextRole: return it.isDir ? QString() : sizeText(it.size);
    case ModifiedRole: return it.modified;
    case ModifiedTextRole: return QLocale().toString(it.modified, QLocale::ShortFormat);
    case TypeRole: return it.type;
    case IconRole: return it.icon;
    case IsImageRole: return it.image;
    case HiddenRole: return it.hidden;
    case LocationRole: return it.location;
    }
    return {};
}

QVariantMap DirModel::get(int row) const
{
    QVariantMap m;
    if (row < 0 || row >= m_items.size())
        return m;
    const QModelIndex idx = index(row);
    const auto names = roleNames();
    for (auto it = names.constBegin(); it != names.constEnd(); ++it)
        m.insert(QString::fromUtf8(it.value()), data(idx, it.key()));
    return m;
}

int DirModel::indexOf(const QString &path) const
{
    for (int i = 0; i < m_items.size(); ++i)
        if (m_items.at(i).path == path)
            return i;
    return -1;
}

QString DirModel::pathAt(int row) const
{
    return row >= 0 && row < m_items.size() ? m_items.at(row).path : QString();
}

qint64 DirModel::totalSize() const
{
    qint64 s = 0;
    for (const Item &it : m_items)
        if (!it.isDir)
            s += it.size;
    return s;
}

bool DirModel::isSystemEntry(const QString &dir, const QString &name)
{
    if (dir != QLatin1String("/"))
        return false;
    static const QStringList sys = {
        QStringLiteral("bin"), QStringLiteral("boot"), QStringLiteral("dev"), QStringLiteral("etc"),
        QStringLiteral("lib"), QStringLiteral("lib32"), QStringLiteral("lib64"), QStringLiteral("libx32"),
        QStringLiteral("lost+found"), QStringLiteral("proc"), QStringLiteral("run"), QStringLiteral("sbin"),
        QStringLiteral("srv"), QStringLiteral("sys"), QStringLiteral("tmp"), QStringLiteral("usr"),
        QStringLiteral("var"), QStringLiteral("snap"), QStringLiteral("cdrom"), QStringLiteral("opt"),
        QStringLiteral("swapfile"), QStringLiteral("live"),
    };
    return sys.contains(name) || name.startsWith(QLatin1String("initrd.img")) || name.startsWith(QLatin1String("vmlinuz"));
}

DirModel::Item DirModel::makeItem(const QFileInfo &fi) const
{
    static Files *files = nullptr;
    if (!files)
        files = Files::instance();
    Item it;
    it.fileName = fi.fileName();
    it.path = fi.absoluteFilePath();
    it.isDir = fi.isDir();
    it.hidden = fi.isHidden() || isSystemEntry(fi.absolutePath(), fi.fileName());
    it.size = it.isDir ? 0 : fi.size();
    it.modified = fi.lastModified();
    it.name = files->displayName(it.path);
    it.type = files->typeName(it.path);
    it.icon = files->iconName(it.path);
    it.image = !it.isDir && files->isImage(it.path);
    it.location = fi.absolutePath();
    return it;
}

void DirModel::sortItems(QList<Item> &items) const
{
    QCollator coll;
    coll.setNumericMode(true);
    coll.setCaseSensitivity(Qt::CaseInsensitive);
    const QString f = m_sortField;
    const bool desc = m_desc;
    std::stable_sort(items.begin(), items.end(), [&](const Item &a, const Item &b) {
        if (a.isDir != b.isDir)
            return a.isDir; // folders first, whatever the order
        int c = 0;
        if (f == QLatin1String("modified"))
            c = a.modified < b.modified ? -1 : (a.modified > b.modified ? 1 : 0);
        else if (f == QLatin1String("size"))
            c = a.size < b.size ? -1 : (a.size > b.size ? 1 : 0);
        else if (f == QLatin1String("type"))
            c = coll.compare(a.type, b.type);
        if (c == 0)
            c = coll.compare(a.name, b.name);
        return desc ? c > 0 : c < 0;
    });
}

void DirModel::reload()
{
    if (!m_search.isEmpty())
        return;
    QList<Item> items;
    if (!m_path.isEmpty() && QFileInfo(m_path).isDir()) {
        QDir dir(m_path);
        const auto list = dir.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System);
        for (const QFileInfo &fi : list) {
            Item it = makeItem(fi);
            if (it.hidden && !m_showHidden)
                continue;
            items << it;
        }
    }
    sortItems(items);
    beginResetModel();
    m_items = items;
    endResetModel();
    Q_EMIT countChanged();
}

void DirModel::refresh()
{
    if (m_search.isEmpty())
        reload();
    else {
        const QString q = m_search;
        m_search.clear();
        setSearchText(q);
    }
}

void DirModel::setPath(const QString &p)
{
    if (m_path == p)
        return;
    stopSearch();
    if (!m_watcher.directories().isEmpty())
        m_watcher.removePaths(m_watcher.directories());
    m_path = p;
    if (QFileInfo(p).isDir())
        m_watcher.addPath(p);
    if (!m_search.isEmpty()) {
        m_search.clear();
        Q_EMIT searchTextChanged();
    }
    reload();
    Q_EMIT pathChanged();
}

void DirModel::setShowHidden(bool s)
{
    if (m_showHidden == s)
        return;
    m_showHidden = s;
    Q_EMIT showHiddenChanged();
    refresh();
}

void DirModel::setSortField(const QString &f)
{
    if (m_sortField == f)
        return;
    m_sortField = f;
    beginResetModel();
    sortItems(m_items);
    endResetModel();
    Q_EMIT sortChanged();
}

void DirModel::setSortDescending(bool d)
{
    if (m_desc == d)
        return;
    m_desc = d;
    beginResetModel();
    sortItems(m_items);
    endResetModel();
    Q_EMIT sortChanged();
}

void DirModel::stopSearch()
{
    m_searchTimer.stop();
    if (m_iter) {
        m_iter.reset();
        Q_EMIT searchingChanged();
    }
}

void DirModel::setSearchText(const QString &t)
{
    const QString q = t.trimmed();
    if (q == m_search)
        return;
    stopSearch();
    m_search = q;
    Q_EMIT searchTextChanged();
    if (q.isEmpty()) {
        reload();
        return;
    }
    beginResetModel();
    m_items.clear();
    endResetModel();
    Q_EMIT countChanged();
    if (!QFileInfo(m_path).isDir())
        return;
    QDir::Filters filters = QDir::AllEntries | QDir::NoDotAndDotDot;
    if (m_showHidden)
        filters |= QDir::Hidden;
    m_iter = std::make_unique<QDirIterator>(m_path, filters, QDirIterator::Subdirectories);
    Q_EMIT searchingChanged();
    m_searchTimer.start();
}

void DirModel::searchStep()
{
    if (!m_iter)
        return;
    static const QStringList skip = {QStringLiteral("/proc"), QStringLiteral("/sys"), QStringLiteral("/dev"),
                                     QStringLiteral("/run")};
    QList<Item> found;
    int budget = 1500;
    while (budget-- > 0 && m_iter->hasNext()) {
        const QString p = m_iter->next();
        bool skipIt = false;
        for (const QString &s : skip)
            if (p.startsWith(s + QLatin1Char('/')) || p == s)
                skipIt = true;
        if (skipIt)
            continue;
        const QFileInfo fi = m_iter->fileInfo();
        if (!fi.fileName().contains(m_search, Qt::CaseInsensitive))
            continue;
        if (!m_showHidden && isSystemEntry(fi.absolutePath(), fi.fileName()))
            continue;
        found << makeItem(fi);
    }
    if (!found.isEmpty() && m_items.size() < 5000) {
        beginInsertRows({}, int(m_items.size()), int(m_items.size() + found.size() - 1));
        m_items << found;
        endInsertRows();
        Q_EMIT countChanged();
    }
    if (!m_iter->hasNext() || m_items.size() >= 5000) {
        stopSearch();
        // Final order once everything is in.
        beginResetModel();
        sortItems(m_items);
        endResetModel();
    }
}
