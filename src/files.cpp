// SPDX-License-Identifier: GPL-3.0-or-later
#include "files.h"
#include "compat.h"
#include "desktopentry.h"
#include "launcher.h"

#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QLocale>
#include <QMimeDatabase>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QUrl>

static QString loc(QStandardPaths::StandardLocation l, const QString &fallback)
{
    const QString p = QStandardPaths::writableLocation(l);
    return p.isEmpty() ? QDir::homePath() + QLatin1Char('/') + fallback : p;
}

Files::Files(QObject *parent)
    : QObject(parent)
{
}

Files *Files::create(QQmlEngine *engine, QJSEngine *) { return new Files(engine); }

QString Files::home() const { return QDir::homePath(); }
QString Files::desktop() const
{
    // A desktop folder always exists, as users expect; never show $HOME itself.
    QString p = QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
    if (p.isEmpty() || p == QDir::homePath())
        p = QDir::homePath() + QStringLiteral("/Desktop");
    QDir().mkpath(p);
    return p;
}
QString Files::documents() const { return loc(QStandardPaths::DocumentsLocation, QStringLiteral("Documents")); }
QString Files::downloads() const { return loc(QStandardPaths::DownloadLocation, QStringLiteral("Downloads")); }
QString Files::music() const { return loc(QStandardPaths::MusicLocation, QStringLiteral("Music")); }
QString Files::pictures() const { return loc(QStandardPaths::PicturesLocation, QStringLiteral("Pictures")); }
QString Files::videos() const { return loc(QStandardPaths::MoviesLocation, QStringLiteral("Videos")); }

QString Files::trash() const
{
    QString data = qEnvironmentVariable("XDG_DATA_HOME");
    if (data.isEmpty())
        data = QDir::homePath() + QStringLiteral("/.local/share");
    return data + QStringLiteral("/Trash/files");
}

QString Files::iconName(const QString &path) const
{
    const QFileInfo fi(path);
    if (fi.isDir()) {
        if (path == home()) return QStringLiteral("user-home");
        if (path == desktop()) return QStringLiteral("user-desktop");
        if (path == documents()) return QStringLiteral("folder-documents");
        if (path == downloads()) return QStringLiteral("folder-download");
        if (path == music()) return QStringLiteral("folder-music");
        if (path == pictures()) return QStringLiteral("folder-pictures");
        if (path == videos()) return QStringLiteral("folder-videos");
        return QStringLiteral("folder");
    }
    if (path.endsWith(QLatin1String(".desktop"))) {
        const DesktopEntry e = DesktopEntry::fromFile(path);
        if (!e.icon().isEmpty())
            return e.icon();
    }
    switch (Compat::kindForPath(path)) {
    case Compat::WindowsExe: {
        const QString extracted = Compat::instance()->exeIcon(path);
        return extracted.isEmpty() ? QStringLiteral("qrc:/qt/qml/Vitrum/icons/exe.svg") : extracted;
    }
    case Compat::WindowsInstaller: return QStringLiteral("qrc:/qt/qml/Vitrum/icons/msi.svg");
    case Compat::WindowsBatch:
    case Compat::WindowsScript: return QStringLiteral("qrc:/qt/qml/Vitrum/icons/bat.svg");
    case Compat::WindowsShortcut: return QStringLiteral("qrc:/qt/qml/Vitrum/icons/exe.svg");
    case Compat::WindowsRegistry: return QStringLiteral("qrc:/qt/qml/Vitrum/icons/reg.svg");
    case Compat::JavaArchive: return QStringLiteral("qrc:/qt/qml/Vitrum/icons/jar.svg");
    case Compat::NotWindows: break;
    }
    static QMimeDatabase db;
    const QMimeType mt = db.mimeTypeForFile(fi);
    return mt.iconName() + QLatin1Char('|') + mt.genericIconName();
}

QString Files::typeName(const QString &path) const
{
    const QFileInfo fi(path);
    if (fi.isDir())
        return QStringLiteral("File folder");
    const QString compat = Compat::instance()->typeName(path);
    if (!compat.isEmpty())
        return compat;
    static QMimeDatabase db;
    return db.mimeTypeForFile(fi).comment();
}

QString Files::formatSize(qint64 bytes) const
{
    if (bytes < 0)
        return {};
    return QLocale().formattedDataSize(bytes, 1, QLocale::DataSizeTraditionalFormat);
}

bool Files::isDir(const QString &path) const { return QFileInfo(path).isDir(); }
bool Files::exists(const QString &path) const { return QFileInfo::exists(path); }

QString Files::parentDir(const QString &path) const
{
    QDir d(path);
    if (!d.cdUp())
        return path;
    return d.absolutePath();
}

QString Files::fileName(const QString &path) const { return QFileInfo(path).fileName(); }

QString Files::displayName(const QString &path) const
{
    if (path == QLatin1String("/"))
        return QStringLiteral("Local Disk (/)");
    if (path == home())
        return QStringLiteral("Home");
    if (path.endsWith(QLatin1String(".desktop"))) {
        const DesktopEntry e = DesktopEntry::fromFile(path);
        if (e.isValid() && !e.name().isEmpty())
            return e.name();
    }
    return QFileInfo(path).fileName();
}

QString Files::toLocal(const QVariant &v) const
{
    const QUrl u = v.toUrl();
    if (u.isLocalFile())
        return u.toLocalFile();
    return v.toString();
}

QString Files::toUrl(const QString &path) const { return QUrl::fromLocalFile(path).toString(); }

static QString uniqueName(const QString &dir, const QString &base)
{
    QString candidate = dir + QLatin1Char('/') + base;
    if (!QFileInfo::exists(candidate))
        return candidate;
    const QFileInfo fi(base);
    const QString stem = fi.completeBaseName().isEmpty() ? base : fi.completeBaseName();
    const QString ext = fi.suffix().isEmpty() ? QString() : QLatin1Char('.') + fi.suffix();
    for (int i = 2; i < 1000; ++i) {
        candidate = QStringLiteral("%1/%2 (%3)%4").arg(dir, stem).arg(i).arg(ext);
        if (!QFileInfo::exists(candidate))
            return candidate;
    }
    return {};
}

QString Files::makeFolder(const QString &parent, const QString &baseName)
{
    const QString path = uniqueName(parent, baseName);
    if (path.isEmpty() || !QDir().mkpath(path))
        return {};
    Q_EMIT changed(parent);
    return path;
}

QString Files::makeFile(const QString &parent, const QString &baseName)
{
    const QString path = uniqueName(parent, baseName);
    QFile f(path);
    if (path.isEmpty() || !f.open(QIODevice::WriteOnly))
        return {};
    Q_EMIT changed(parent);
    return path;
}

bool Files::rename(const QString &path, const QString &newName)
{
    if (newName.isEmpty() || newName.contains(QLatin1Char('/')))
        return false;
    const QFileInfo fi(path);
    const QString target = fi.absolutePath() + QLatin1Char('/') + newName;
    if (QFileInfo::exists(target))
        return false;
    const bool ok = QFile::rename(path, target);
    if (ok)
        Q_EMIT changed(fi.absolutePath());
    return ok;
}

bool Files::moveToTrash(const QStringList &paths)
{
    bool ok = true;
    for (const QString &p : paths)
        ok = QFile::moveToTrash(p) && ok;
    if (!paths.isEmpty())
        Q_EMIT changed(parentDir(paths.first()));
    return ok;
}

bool Files::emptyTrash()
{
    const QString files = trash();
    const QString info = QFileInfo(files).absolutePath() + QStringLiteral("/info");
    bool ok = QDir(files).removeRecursively();
    QDir(info).removeRecursively();
    QDir().mkpath(files);
    QDir().mkpath(info);
    Q_EMIT changed(files);
    return ok;
}

int Files::trashCount() const
{
    return int(QDir(trash()).entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden).size());
}

void Files::copy(const QStringList &paths)
{
    m_clipboard = paths;
    m_cut = false;
    Q_EMIT clipboardChanged();
}

void Files::cut(const QStringList &paths)
{
    m_clipboard = paths;
    m_cut = true;
    Q_EMIT clipboardChanged();
}

static bool copyRecursive(const QString &src, const QString &dst)
{
    const QFileInfo fi(src);
    if (fi.isSymLink())
        return QFile::link(fi.symLinkTarget(), dst);
    if (!fi.isDir())
        return QFile::copy(src, dst);
    if (dst.startsWith(src + QLatin1Char('/')))
        return false; // into itself
    if (!QDir().mkpath(dst))
        return false;
    const QDir dir(src);
    bool ok = true;
    for (const QString &e : dir.entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System))
        ok = copyRecursive(src + QLatin1Char('/') + e, dst + QLatin1Char('/') + e) && ok;
    return ok;
}

bool Files::paste(const QString &targetDir)
{
    if (m_clipboard.isEmpty() || !QFileInfo(targetDir).isDir())
        return false;
    bool ok = true;
    for (const QString &src : std::as_const(m_clipboard)) {
        const QString name = QFileInfo(src).fileName();
        QString dst = targetDir + QLatin1Char('/') + name;
        if (m_cut && QFileInfo(src).absolutePath() == QFileInfo(targetDir).absoluteFilePath())
            continue;
        if (QFileInfo::exists(dst))
            dst = uniqueName(targetDir, m_cut ? name : QFileInfo(name).completeBaseName() + QStringLiteral(" - Copy")
                                                          + (QFileInfo(name).suffix().isEmpty() ? QString() : QLatin1Char('.') + QFileInfo(name).suffix()));
        if (m_cut) {
            if (!QFile::rename(src, dst)) {
                ok = copyRecursive(src, dst) && (QFileInfo(src).isDir() ? QDir(src).removeRecursively() : QFile::remove(src)) && ok;
            }
        } else {
            ok = copyRecursive(src, dst) && ok;
        }
    }
    if (m_cut) {
        m_clipboard.clear();
        Q_EMIT clipboardChanged();
    }
    Q_EMIT changed(targetDir);
    return ok;
}

QVariantList Files::volumes() const
{
    QVariantList out;
    for (const QStorageInfo &s : QStorageInfo::mountedVolumes()) {
        if (!s.isValid() || !s.isReady())
            continue;
        const QString root = s.rootPath();
        const QByteArray fs = s.fileSystemType();
        const bool interesting = root == QLatin1String("/") || root.startsWith(QLatin1String("/media/"))
            || root.startsWith(QLatin1String("/run/media/")) || root.startsWith(QLatin1String("/mnt/"))
            || (root == QLatin1String("/home") && s.device() != QStorageInfo::root().device());
        if (!interesting || fs == "tmpfs" || fs == "overlay" || fs == "squashfs")
            continue;
        QString name = s.displayName();
        if (root == QLatin1String("/"))
            name = QStringLiteral("Local Disk");
        out << QVariantMap{
            {QStringLiteral("name"), name},
            {QStringLiteral("path"), root},
            {QStringLiteral("total"), s.bytesTotal()},
            {QStringLiteral("free"), s.bytesAvailable()},
            {QStringLiteral("removable"), !root.startsWith(QLatin1String("/home")) && root != QLatin1String("/")},
        };
    }
    if (out.isEmpty()) {
        const QStorageInfo r = QStorageInfo::root();
        out << QVariantMap{{QStringLiteral("name"), QStringLiteral("Local Disk")}, {QStringLiteral("path"), QStringLiteral("/")},
                           {QStringLiteral("total"), r.bytesTotal()}, {QStringLiteral("free"), r.bytesAvailable()},
                           {QStringLiteral("removable"), false}};
    }
    return out;
}

QVariantMap Files::info(const QString &path) const
{
    const QFileInfo fi(path);
    qint64 size = fi.size();
    int count = 0;
    if (fi.isDir()) {
        size = 0;
        QDirIterator it(path, QDir::Files | QDir::Hidden | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
        while (it.hasNext() && count < 20000) {
            it.next();
            size += it.fileInfo().size();
            ++count;
        }
    }
    return {
        {QStringLiteral("name"), displayName(path)},
        {QStringLiteral("path"), fi.absoluteFilePath()},
        {QStringLiteral("type"), typeName(path)},
        {QStringLiteral("icon"), iconName(path)},
        {QStringLiteral("size"), formatSize(size)},
        {QStringLiteral("files"), count},
        {QStringLiteral("modified"), QLocale().toString(fi.lastModified(), QLocale::LongFormat)},
        {QStringLiteral("created"), QLocale().toString(fi.birthTime().isValid() ? fi.birthTime() : fi.metadataChangeTime(), QLocale::LongFormat)},
        {QStringLiteral("owner"), fi.owner()},
        {QStringLiteral("readOnly"), !fi.isWritable()},
        {QStringLiteral("hidden"), fi.isHidden()},
    };
}

QVariantMap Files::desktopFileInfo(const QString &path) const
{
    const DesktopEntry e = DesktopEntry::fromFile(path);
    if (!e.isValid())
        return {};
    return {{QStringLiteral("name"), e.name()}, {QStringLiteral("icon"), e.icon()}};
}

bool Files::launchDesktopFile(const QString &path)
{
    const DesktopEntry e = DesktopEntry::fromFile(path);
    if (!e.isValid())
        return false;
    if (e.type() == QLatin1String("Link"))
        return Launcher::instance()->openPath(e.value(QStringLiteral("URL")));
    return Launcher::instance()->launchEntry(e);
}

bool Files::isImage(const QString &path) const
{
    static QMimeDatabase db;
    const QString name = db.mimeTypeForFile(path).name();
    return name == QLatin1String("image/png") || name == QLatin1String("image/jpeg") || name == QLatin1String("image/gif")
        || name == QLatin1String("image/webp") || name == QLatin1String("image/svg+xml") || name == QLatin1String("image/bmp");
}

bool Files::isText(const QString &path) const
{
    static QMimeDatabase db;
    const QMimeType mt = db.mimeTypeForFile(path);
    if (QFileInfo(path).size() > 8 * 1024 * 1024)
        return false;
    return mt.inherits(QStringLiteral("text/plain")) && !path.endsWith(QLatin1String(".desktop"))
        && Compat::kindForPath(path) == Compat::NotWindows;
}

QString Files::readText(const QString &path) const
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly))
        return {};
    return QString::fromUtf8(f.readAll());
}

bool Files::writeText(const QString &path, const QString &text)
{
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    const bool ok = f.write(text.toUtf8()) >= 0;
    Q_EMIT changed(QFileInfo(path).absolutePath());
    return ok;
}

QStringList Files::siblingImages(const QString &path) const
{
    const QDir dir = QFileInfo(path).absoluteDir();
    QStringList out;
    for (const QFileInfo &fi : dir.entryInfoList(QDir::Files, QDir::Name | QDir::IgnoreCase))
        if (isImage(fi.absoluteFilePath()))
            out << fi.absoluteFilePath();
    return out;
}
