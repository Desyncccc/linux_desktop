// SPDX-License-Identifier: GPL-3.0-or-later
#include "appmodel.h"
#include "compat.h"
#include "launcher.h"

#include <QCryptographicHash>

#include <QDir>
#include <QUrl>
#include <QDirIterator>
#include <QStandardPaths>
#include <algorithm>

static AppModel *s_apps = nullptr;

AppModel::AppModel(QObject *parent)
    : QAbstractListModel(parent)
{
    m_reloadTimer.setSingleShot(true);
    m_reloadTimer.setInterval(800);
    connect(&m_reloadTimer, &QTimer::timeout, this, &AppModel::reload);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_reloadTimer.start(); });
    QMetaObject::invokeMethod(this, [this] {
        connect(Compat::instance(), &Compat::programsChanged, this, [this] { m_reloadTimer.start(); });
    }, Qt::QueuedConnection);
    reload();
}

AppModel *AppModel::instance()
{
    if (!s_apps)
        s_apps = new AppModel;
    return s_apps;
}

AppModel *AppModel::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

QStringList AppModel::applicationDirs()
{
    QStringList dirs;
    QString home = qEnvironmentVariable("XDG_DATA_HOME");
    if (home.isEmpty())
        home = QDir::homePath() + QStringLiteral("/.local/share");
    dirs << home + QStringLiteral("/applications");
    QString sys = qEnvironmentVariable("XDG_DATA_DIRS");
    if (sys.isEmpty())
        sys = QStringLiteral("/usr/local/share:/usr/share");
    for (const QString &d : sys.split(QLatin1Char(':'), Qt::SkipEmptyParts))
        dirs << d + QStringLiteral("/applications");
    // Flatpak exports
    dirs << QDir::homePath() + QStringLiteral("/.local/share/flatpak/exports/share/applications")
         << QStringLiteral("/var/lib/flatpak/exports/share/applications");
    dirs.removeDuplicates();
    return dirs;
}

QString AppModel::mainCategory(const QStringList &cats)
{
    static const QList<QPair<QString, QString>> map = {
        {QStringLiteral("Settings"), QStringLiteral("Settings")},
        {QStringLiteral("System"), QStringLiteral("System Tools")},
        {QStringLiteral("Development"), QStringLiteral("Development")},
        {QStringLiteral("Game"), QStringLiteral("Games")},
        {QStringLiteral("Graphics"), QStringLiteral("Graphics")},
        {QStringLiteral("Network"), QStringLiteral("Internet")},
        {QStringLiteral("AudioVideo"), QStringLiteral("Multimedia")},
        {QStringLiteral("Audio"), QStringLiteral("Multimedia")},
        {QStringLiteral("Video"), QStringLiteral("Multimedia")},
        {QStringLiteral("Office"), QStringLiteral("Office")},
        {QStringLiteral("Education"), QStringLiteral("Education")},
        {QStringLiteral("Science"), QStringLiteral("Education")},
        {QStringLiteral("X-Windows"), QStringLiteral("Windows Programs")},
        {QStringLiteral("Utility"), QStringLiteral("Accessories")},
        {QStringLiteral("X-Vitrum-Accessories"), QStringLiteral("Accessories")},
        {QStringLiteral("X-Vitrum-System-Tools"), QStringLiteral("System Tools")},
    };
    for (const auto &p : map)
        if (cats.contains(p.first))
            return p.second;
    return QStringLiteral("Accessories");
}

void AppModel::reload()
{
    const QString desktop = qEnvironmentVariable("XDG_CURRENT_DESKTOP", QStringLiteral("Vitrum"));
    QList<DesktopEntry> entries;
    QSet<QString> seen;
    const QStringList dirs = applicationDirs();

    if (!m_watcher.directories().isEmpty())
        m_watcher.removePaths(m_watcher.directories());

    for (const QString &dir : dirs) {
        if (!QDir(dir).exists())
            continue;
        m_watcher.addPath(dir);
        QDirIterator it(dir, {QStringLiteral("*.desktop")}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString path = it.next();
            // desktop id: relative path with '/' replaced by '-'
            QString id = QDir(dir).relativeFilePath(path);
            id.replace(QLatin1Char('/'), QLatin1Char('-'));
            if (seen.contains(id))
                continue; // earlier dirs take precedence
            seen.insert(id);
            DesktopEntry e = DesktopEntry::fromFile(path, id);
            if (!e.isVisibleIn(desktop))
                continue;
            if (isRuntimePlumbing(e))
                continue;
            const QString tryExec = e.tryExec();
            if (!tryExec.isEmpty() && QStandardPaths::findExecutable(tryExec).isEmpty() && !QFileInfo(tryExec).isExecutable())
                continue;
            entries << e;
        }
    }
    // Programs installed into the Windows app support prefix.
    for (const QString &lnk : Compat::instance()->startMenuShortcuts()) {
        const QString name = QFileInfo(lnk).completeBaseName();
        const QString id = QStringLiteral("vitrum-windows-")
            + QString::fromLatin1(QCryptographicHash::hash(lnk.toUtf8(), QCryptographicHash::Sha1).toHex().left(12))
            + QStringLiteral(".desktop");
        QByteArray data = "[Desktop Entry]\nType=Application\nName=" + name.toUtf8()
            + "\nIcon=:/qt/qml/Vitrum/icons/exe.svg\nExec=vitrum-open\nCategories=X-Windows;\nX-Vitrum-Target=" + lnk.toUtf8() + "\n";
        entries << DesktopEntry::fromData(data, id);
    }

    // Programs built into the shell itself. Launching one opens it in-process.
    struct Builtin { const char *kind, *name, *icon, *category, *keywords; };
    static const Builtin builtins[] = {
        {"explorer", "Windows Explorer", "folder", "Accessories", "files;folders;explorer;browse;"},
        {"notepad", "Notepad", "notepad", "Accessories", "text;editor;notes;"},
        {"calculator", "Calculator", "calculator", "Accessories", "calc;math;numbers;"},
        {"paint", "Paint", "paint", "Accessories", "draw;image;picture;brush;"},
        {"stickynotes", "Sticky Notes", "stickynotes", "Accessories", "notes;memo;reminder;"},
        {"snippingtool", "Snipping Tool", "snippingtool", "Accessories", "screenshot;capture;snip;"},
        {"photos", "Photo Viewer", "image-file", "Accessories", "pictures;images;photos;"},
        {"taskmanager", "Task Manager", "taskmanager", "System Tools", "processes;performance;kill;"},
        {"run", "Run", "run", "System Tools", "command;execute;"},
        {"settings", "Control Panel", "settings", "System Tools", "settings;control;preferences;"},
    };
    for (const Builtin &b : builtins) {
        const QString id = QStringLiteral("vitrum-builtin-%1.desktop").arg(QLatin1String(b.kind));
        if (seen.contains(id))
            continue;
        const QByteArray data = QByteArray("[Desktop Entry]\nType=Application\nName=") + b.name
            + "\nIcon=:/qt/qml/Vitrum/icons/" + b.icon + ".svg\nExec=true\nCategories=X-Vitrum-" + QByteArray(b.category).replace(' ', '-')
            + ";\nKeywords=" + b.keywords + "\nX-Vitrum-Internal=" + b.kind + "\n";
        entries << DesktopEntry::fromData(data, id);
    }

    std::sort(entries.begin(), entries.end(), [](const DesktopEntry &a, const DesktopEntry &b) {
        return a.name().compare(b.name(), Qt::CaseInsensitive) < 0;
    });

    beginResetModel();
    m_entries = entries;
    m_index.clear();
    for (int i = 0; i < m_entries.size(); ++i)
        m_index.insert(m_entries.at(i).desktopId(), i);
    endResetModel();
    Q_EMIT countChanged();
}

int AppModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_entries.size());
}

QVariant AppModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_entries.size())
        return {};
    const DesktopEntry &e = m_entries.at(index.row());
    switch (role) {
    case Qt::DisplayRole:
    case NameRole: return e.name();
    case DesktopIdRole: return e.desktopId();
    case GenericNameRole: return e.genericName();
    case CommentRole: return e.comment();
    case IconRole: return e.icon();
    case CategoryRole: return mainCategory(e.categories());
    case KeywordsRole: return e.keywords();
    }
    return {};
}

QHash<int, QByteArray> AppModel::roleNames() const
{
    return {
        {DesktopIdRole, "desktopId"}, {NameRole, "name"}, {GenericNameRole, "genericName"},
        {CommentRole, "comment"}, {IconRole, "iconName"}, {CategoryRole, "category"},
        {KeywordsRole, "keywords"},
    };
}

const DesktopEntry *AppModel::entry(const QString &desktopId) const
{
    const auto it = m_index.constFind(desktopId);
    return it == m_index.constEnd() ? nullptr : &m_entries.at(*it);
}

QVariantMap AppModel::toMap(const DesktopEntry &e) const
{
    return {
        {QStringLiteral("desktopId"), e.desktopId()},
        {QStringLiteral("name"), e.name()},
        {QStringLiteral("genericName"), e.genericName()},
        {QStringLiteral("comment"), e.comment()},
        {QStringLiteral("iconName"), e.icon()},
        {QStringLiteral("category"), mainCategory(e.categories())},
    };
}

QVariantMap AppModel::get(const QString &desktopId) const
{
    const DesktopEntry *e = entry(desktopId);
    return e ? toMap(*e) : QVariantMap{};
}

QVariantList AppModel::all() const
{
    QVariantList out;
    for (const auto &e : m_entries)
        out << toMap(e);
    return out;
}

QVariantList AppModel::appsForIds(const QStringList &ids) const
{
    QVariantList out;
    for (const QString &id : ids)
        if (const DesktopEntry *e = entry(id))
            out << toMap(*e);
    return out;
}

QVariantList AppModel::search(const QString &query, int limit) const
{
    const QString q = query.trimmed().toLower();
    if (q.isEmpty())
        return {};
    QList<QPair<int, int>> scored; // score, index
    for (int i = 0; i < m_entries.size(); ++i) {
        const DesktopEntry &e = m_entries.at(i);
        const QString name = e.name().toLower();
        int score = 0;
        if (name == q)
            score = 100;
        else if (name.startsWith(q))
            score = 80;
        else {
            const QStringList words = name.split(QLatin1Char(' '), Qt::SkipEmptyParts);
            for (const QString &w : words)
                if (w.startsWith(q))
                    score = std::max(score, 60);
            if (!score && name.contains(q))
                score = 40;
        }
        if (!score) {
            if (e.genericName().toLower().contains(q))
                score = 30;
            else {
                for (const QString &k : e.keywords())
                    if (k.toLower().startsWith(q))
                        score = std::max(score, 25);
                if (!score && e.comment().toLower().contains(q))
                    score = 10;
                if (!score && e.desktopId().toLower().contains(q))
                    score = 8;
            }
        }
        if (score)
            scored.append({score, i});
    }
    std::stable_sort(scored.begin(), scored.end(), [](auto a, auto b) { return a.first > b.first; });
    QVariantList out;
    for (int i = 0; i < scored.size() && i < limit; ++i)
        out << toMap(m_entries.at(scored.at(i).second));
    return out;
}

QVariantList AppModel::categoryGroups() const
{
    QMap<QString, QVariantList> groups;
    for (const auto &e : m_entries)
        groups[mainCategory(e.categories())] << toMap(e);
    QVariantList out;
    for (auto it = groups.constBegin(); it != groups.constEnd(); ++it)
        out << QVariantMap{{QStringLiteral("category"), it.key()}, {QStringLiteral("apps"), it.value()}};
    return out;
}

QString AppModel::idForAppId(const QString &appId) const
{
    if (appId.isEmpty())
        return {};
    const QString lower = appId.toLower();
    const QStringList candidates = {
        appId + QStringLiteral(".desktop"),
        lower + QStringLiteral(".desktop"),
        appId.section(QLatin1Char('.'), -1) + QStringLiteral(".desktop"),
        lower.section(QLatin1Char('.'), -1) + QStringLiteral(".desktop"),
    };
    for (const QString &c : candidates)
        if (m_index.contains(c))
            return c;
    for (const auto &e : m_entries) {
        if (e.startupWMClass().compare(appId, Qt::CaseInsensitive) == 0)
            return e.desktopId();
    }
    for (const auto &e : m_entries) {
        const QString id = e.desktopId().toLower();
        if (id.endsWith(QLatin1Char('.') + lower + QStringLiteral(".desktop")) || id.startsWith(lower + QLatin1Char('-')))
            return e.desktopId();
    }
    for (const auto &e : m_entries) {
        const QStringList exec = DesktopEntry::tokenizeExec(e.exec());
        if (!exec.isEmpty() && QFileInfo(exec.first()).fileName().compare(appId, Qt::CaseInsensitive) == 0)
            return e.desktopId();
    }
    return {};
}

bool AppModel::isRuntimePlumbing(const DesktopEntry &e)
{
    // The Windows runtime's own launchers/tools stay out of sight.
    const QString id = e.desktopId().toLower();
    if (id.startsWith(QLatin1String("wine")) || e.categories().contains(QLatin1String("Wine")))
        return true;
    const QStringList exec = DesktopEntry::tokenizeExec(e.exec());
    if (!exec.isEmpty()) {
        const QString prog = QFileInfo(exec.first()).fileName();
        if (prog == QLatin1String("wine") || prog == QLatin1String("wine64") || prog == QLatin1String("winetricks"))
            return true;
    }
    return false;
}

bool AppModel::launch(const QString &desktopId, const QStringList &files)
{
    const DesktopEntry *e = entry(desktopId);
    if (!e)
        return false;
    const QString internal = e->value(QStringLiteral("X-Vitrum-Internal"));
    if (!internal.isEmpty()) {
        Q_EMIT internalRequested(internal, files.isEmpty() ? QString() : files.first());
        Q_EMIT launched(desktopId);
        return true;
    }
    const QString target = e->value(QStringLiteral("X-Vitrum-Target"));
    if (!target.isEmpty()) {
        const bool ok = Launcher::instance()->openFile(target).isEmpty();
        if (ok)
            Q_EMIT launched(desktopId);
        return ok;
    }
    const bool ok = Launcher::instance()->launchEntry(*e, files);
    if (ok)
        Q_EMIT launched(desktopId);
    return ok;
}

QList<DesktopEntry> AppModel::autostartEntries()
{
    QStringList dirs;
    QString home = qEnvironmentVariable("XDG_CONFIG_HOME");
    if (home.isEmpty())
        home = QDir::homePath() + QStringLiteral("/.config");
    dirs << home + QStringLiteral("/autostart");
    QString sys = qEnvironmentVariable("XDG_CONFIG_DIRS");
    if (sys.isEmpty())
        sys = QStringLiteral("/etc/xdg");
    for (const QString &d : sys.split(QLatin1Char(':'), Qt::SkipEmptyParts))
        dirs << d + QStringLiteral("/autostart");

    const QString desktop = qEnvironmentVariable("XDG_CURRENT_DESKTOP", QStringLiteral("Vitrum"));
    QSet<QString> seen;
    QList<DesktopEntry> out;
    for (const QString &dir : dirs) {
        const auto files = QDir(dir).entryInfoList({QStringLiteral("*.desktop")}, QDir::Files);
        for (const QFileInfo &fi : files) {
            if (seen.contains(fi.fileName()))
                continue;
            seen.insert(fi.fileName());
            DesktopEntry e = DesktopEntry::fromFile(fi.filePath());
            if (e.hidden() || e.type() != QLatin1String("Application"))
                continue;
            // Autostart entries may set NoDisplay but still run; check show-in rules manually.
            const QStringList only = e.onlyShowIn();
            if (!only.isEmpty() && !only.contains(desktop, Qt::CaseInsensitive))
                continue;
            if (e.notShowIn().contains(desktop, Qt::CaseInsensitive))
                continue;
            if (e.boolValue(QStringLiteral("X-GNOME-Autostart-enabled")) == false
                && !e.value(QStringLiteral("X-GNOME-Autostart-enabled")).isEmpty())
                continue;
            const QString tryExec = e.tryExec();
            if (!tryExec.isEmpty() && QStandardPaths::findExecutable(tryExec).isEmpty())
                continue;
            out << e;
        }
    }
    return out;
}

bool AppModel::isProgramFile(const QString &path) const
{
    const QFileInfo fi(path);
    if (fi.isDir() || !fi.exists())
        return false;
    if (path.endsWith(QLatin1String(".desktop")))
        return true;
    const Compat::Kind k = Compat::kindForPath(path);
    if (k == Compat::WindowsExe || k == Compat::WindowsShortcut || k == Compat::JavaArchive || k == Compat::WindowsBatch)
        return true;
    return fi.isExecutable();
}

QString AppModel::ensureEntryForFile(const QString &path)
{
    if (!isProgramFile(path))
        return {};
    if (path.endsWith(QLatin1String(".desktop"))) {
        const QString id = QFileInfo(path).fileName();
        if (m_index.contains(id))
            return id;
    }
    QString dataHome = qEnvironmentVariable("XDG_DATA_HOME");
    if (dataHome.isEmpty())
        dataHome = QDir::homePath() + QStringLiteral("/.local/share");
    const QString dir = dataHome + QStringLiteral("/applications");
    QDir().mkpath(dir);
    const QString id = QStringLiteral("vitrum-pinned-")
        + QString::fromLatin1(QCryptographicHash::hash(path.toUtf8(), QCryptographicHash::Sha1).toHex().left(12))
        + QStringLiteral(".desktop");
    QString name = path.endsWith(QLatin1String(".desktop")) ? DesktopEntry::fromFile(path).name() : Compat::prettyName(path);
    QString icon = QStringLiteral(":/qt/qml/Vitrum/icons/app-generic.svg");
    const Compat::Kind k = Compat::kindForPath(path);
    if (k == Compat::WindowsExe) {
        const QString extracted = Compat::instance()->exeIcon(path);
        icon = extracted.isEmpty() ? QStringLiteral(":/qt/qml/Vitrum/icons/exe.svg") : QUrl(extracted).toLocalFile();
    } else if (k == Compat::JavaArchive) {
        icon = QStringLiteral(":/qt/qml/Vitrum/icons/jar.svg");
    } else if (path.endsWith(QLatin1String(".desktop"))) {
        icon = DesktopEntry::fromFile(path).icon();
    }
    QFile f(dir + QLatin1Char('/') + id);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return {};
    QString escaped = path;
    escaped.replace(QLatin1Char('\\'), QStringLiteral("\\\\")).replace(QLatin1Char('"'), QStringLiteral("\\\""));
    f.write("[Desktop Entry]\nType=Application\nName=" + name.toUtf8() + "\nIcon=" + icon.toUtf8()
            + "\nExec=vitrum-open \"" + escaped.toUtf8() + "\"\nX-Vitrum-Target=" + path.toUtf8()
            + "\nNoDisplay=false\nCategories=X-Vitrum-Pinned;\n");
    f.close();
    reload();
    return m_index.contains(id) ? id : QString();
}
