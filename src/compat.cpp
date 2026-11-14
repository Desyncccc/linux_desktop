// SPDX-License-Identifier: GPL-3.0-or-later
#include "compat.h"
#include "launcher.h"

#include <QCryptographicHash>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>
#include <QUrl>

static Compat *s_compat = nullptr;

Compat::Compat(QObject *parent)
    : QObject(parent)
{
    refresh();
}

Compat *Compat::instance()
{
    if (!s_compat)
        s_compat = new Compat;
    return s_compat;
}

Compat *Compat::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

void Compat::refresh()
{
    m_wine.clear();
    const QStringList wineCandidates = {QStringLiteral("wine"), QStringLiteral("wine64"),
                                        QStringLiteral("/opt/wine-stable/bin/wine"), QStringLiteral("/opt/wine-staging/bin/wine"),
                                        QStringLiteral("/usr/lib/wine/wine64"), QStringLiteral("/usr/lib/wine/wine")};
    for (const QString &c : wineCandidates) {
        const QString p = c.startsWith(QLatin1Char('/')) ? (QFileInfo(c).isExecutable() ? c : QString()) : QStandardPaths::findExecutable(c);
        if (!p.isEmpty()) {
            m_wine = p;
            break;
        }
    }
    m_java = QStandardPaths::findExecutable(QStringLiteral("java"));
    m_version.clear();
    if (!m_wine.isEmpty()) {
        QProcess p;
        p.start(m_wine, {QStringLiteral("--version")});
        if (p.waitForFinished(3000))
            m_version = QString::fromUtf8(p.readAllStandardOutput()).trimmed().remove(QLatin1String("wine-"));
    }
    Q_EMIT availabilityChanged();
}

QString Compat::prefix() const
{
    const QString env = qEnvironmentVariable("VITRUM_WINDOWS_PREFIX");
    if (!env.isEmpty())
        return env;
    QString data = qEnvironmentVariable("XDG_DATA_HOME");
    if (data.isEmpty())
        data = QDir::homePath() + QStringLiteral("/.local/share");
    return data + QStringLiteral("/vitrum/windows");
}

Compat::Kind Compat::kindForPath(const QString &path)
{
    const QString ext = QFileInfo(path).suffix().toLower();
    if (ext == QLatin1String("exe") || ext == QLatin1String("com") || ext == QLatin1String("scr"))
        return WindowsExe;
    if (ext == QLatin1String("msi") || ext == QLatin1String("msp"))
        return WindowsInstaller;
    if (ext == QLatin1String("bat") || ext == QLatin1String("cmd"))
        return WindowsBatch;
    if (ext == QLatin1String("lnk"))
        return WindowsShortcut;
    if (ext == QLatin1String("reg"))
        return WindowsRegistry;
    if (ext == QLatin1String("vbs") || ext == QLatin1String("wsf"))
        return WindowsScript;
    if (ext == QLatin1String("jar"))
        return JavaArchive;
    return NotWindows;
}

QString Compat::typeName(const QString &path) const
{
    switch (kindForPath(path)) {
    case WindowsExe: return QStringLiteral("Application");
    case WindowsInstaller: return QStringLiteral("Windows Installer Package");
    case WindowsBatch: return QStringLiteral("Windows Batch File");
    case WindowsShortcut: return QStringLiteral("Shortcut");
    case WindowsRegistry: return QStringLiteral("Registration Entries");
    case WindowsScript: return QStringLiteral("Script File");
    case JavaArchive: return QStringLiteral("Executable Jar File");
    case NotWindows: break;
    }
    return {};
}

QStringList Compat::commandFor(const QString &path) const
{
    const Kind kind = kindForPath(path);
    if (kind == JavaArchive)
        return m_java.isEmpty() ? QStringList() : QStringList{m_java, QStringLiteral("-jar"), path};
    if (kind == NotWindows || m_wine.isEmpty())
        return {};
    switch (kind) {
    case WindowsExe: return {m_wine, path};
    case WindowsInstaller: return {m_wine, QStringLiteral("msiexec"), QStringLiteral("/i"), path};
    case WindowsBatch: return {m_wine, QStringLiteral("wineconsole"), QStringLiteral("cmd"), QStringLiteral("/c"), path};
    case WindowsShortcut: return {m_wine, QStringLiteral("start"), QStringLiteral("/unix"), path};
    case WindowsRegistry: return {m_wine, QStringLiteral("regedit"), path};
    case WindowsScript: return {m_wine, QStringLiteral("wscript"), path};
    default: return {};
    }
}

QProcessEnvironment Compat::environment(const QProcessEnvironment &base) const
{
    QProcessEnvironment env = base;
    env.insert(QStringLiteral("WINEPREFIX"), prefix());
    // Quiet: no debug spew, no host menu entries, no runtime download prompts.
    env.insert(QStringLiteral("WINEDEBUG"), QStringLiteral("-all"));
    env.insert(QStringLiteral("WINEDLLOVERRIDES"), QStringLiteral("winemenubuilder.exe=d;mscoree=d;mshtml=d"));
    env.insert(QStringLiteral("WINE_LARGE_ADDRESS_AWARE"), QStringLiteral("1"));
    // Native Wayland windows (Wine 9+): our compositor has no X server.
    if (!env.contains(QStringLiteral("DISPLAY")))
        env.remove(QStringLiteral("DISPLAY"));
    return env;
}

QString Compat::open(const QString &path, const QStringList &args)
{
    const Kind kind = kindForPath(path);
    if (kind == NotWindows)
        return QStringLiteral("unsupported");
    if (kind == JavaArchive && m_java.isEmpty())
        return QStringLiteral("missing-java");
    if (kind != JavaArchive && m_wine.isEmpty())
        return QStringLiteral("missing-windows");

    QStringList cmd = commandFor(path);
    cmd << args;
    QProcess p;
    p.setProgram(cmd.first());
    p.setArguments(cmd.mid(1));
    p.setProcessEnvironment(environment(Launcher::instance()->clientEnvironment()));
    p.setWorkingDirectory(QFileInfo(path).absolutePath());
    p.setStandardInputFile(QProcess::nullDevice());
    if (!qEnvironmentVariableIsSet("VITRUM_CLIENT_OUTPUT")) {
        p.setStandardOutputFile(Launcher::appLogPath(), QIODevice::Append);
        p.setStandardErrorFile(Launcher::appLogPath(), QIODevice::Append);
    }
    Launcher::appendToAppLog(QStringLiteral("== launching: ") + cmd.join(QLatin1Char(' ')));
    if (!p.startDetached())
        return QStringLiteral("failed");
    if (kind == WindowsInstaller || kind == WindowsExe)
        QTimer::singleShot(15000, this, &Compat::programsChanged); // installers add shortcuts
    return {};
}

void Compat::prepare()
{
    // Initialise the prefix silently in the background, so the first program
    // starts without the runtime's own "updating configuration" window.
    if (m_wine.isEmpty() || m_preparing || QFileInfo::exists(prefix() + QStringLiteral("/system.reg")))
        return;
    QDir().mkpath(prefix());
    m_preparing = true;
    Q_EMIT preparingChanged();
    auto *p = new QProcess(this);
    QProcessEnvironment env = environment(QProcessEnvironment::systemEnvironment());
    env.remove(QStringLiteral("DISPLAY"));
    env.remove(QStringLiteral("WAYLAND_DISPLAY"));
    env.insert(QStringLiteral("WINEDLLOVERRIDES"), env.value(QStringLiteral("WINEDLLOVERRIDES")) + QStringLiteral(";winex11.drv=d;winewayland.drv=d"));
    p->setProcessEnvironment(env);
    p->setStandardOutputFile(QProcess::nullDevice());
    p->setStandardErrorFile(QProcess::nullDevice());
    connect(p, &QProcess::finished, this, [this, p, env] {
        p->deleteLater();
        // Our compositor speaks Wayland only: select the runtime's native
        // Wayland driver, and keep its own desktop integration out of sight.
        auto *reg = new QProcess(this);
        reg->setProcessEnvironment(env);
        reg->setStandardOutputFile(QProcess::nullDevice());
        reg->setStandardErrorFile(QProcess::nullDevice());
        connect(reg, &QProcess::finished, this, [this, reg] {
            reg->deleteLater();
            m_preparing = false;
            Q_EMIT preparingChanged();
        });
        reg->start(m_wine, {QStringLiteral("reg"), QStringLiteral("add"), QStringLiteral("HKCU\\Software\\Wine\\Drivers"),
                            QStringLiteral("/v"), QStringLiteral("Graphics"), QStringLiteral("/d"), QStringLiteral("wayland,x11"),
                            QStringLiteral("/f")});
    });
    p->start(m_wine, {QStringLiteral("wineboot"), QStringLiteral("--init")});
}

static QString cacheDir()
{
    QString cache = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation);
    if (cache.isEmpty())
        cache = QDir::homePath() + QStringLiteral("/.cache");
    return cache + QStringLiteral("/vitrum/exe-icons");
}

QString Compat::exeIcon(const QString &exePath)
{
    if (!QFileInfo::exists(exePath))
        return {};
    const QByteArray key = QCryptographicHash::hash((exePath + QString::number(QFileInfo(exePath).size())).toUtf8(), QCryptographicHash::Sha1).toHex();
    const QString out = cacheDir() + QLatin1Char('/') + QString::fromLatin1(key) + QStringLiteral(".png");
    if (QFileInfo::exists(out))
        return QFileInfo(out).size() > 0 ? QUrl::fromLocalFile(out).toString() : QString();
    if (m_iconJobs.contains(exePath) || QStandardPaths::findExecutable(QStringLiteral("wrestool")).isEmpty()
        || QStandardPaths::findExecutable(QStringLiteral("icotool")).isEmpty())
        return {};
    m_iconJobs.insert(exePath);
    QDir().mkpath(cacheDir());
    // Extract the largest icon from the executable's resources.
    const QString tmp = cacheDir() + QLatin1Char('/') + QString::fromLatin1(key) + QStringLiteral(".d");
    const QString script = QStringLiteral(
        "set -e; mkdir -p \"$2\"; wrestool -x -t 14 \"$1\" > \"$2/i.ico\" 2>/dev/null || true; "
        "if [ -s \"$2/i.ico\" ]; then icotool -x -o \"$2\" \"$2/i.ico\" 2>/dev/null || true; fi; "
        "best=$(ls -S \"$2\"/*.png 2>/dev/null | head -n1); "
        "if [ -n \"$best\" ]; then cp \"$best\" \"$3\"; else : > \"$3\"; fi; rm -rf \"$2\"");
    auto *p = new QProcess(this);
    connect(p, &QProcess::finished, this, [this, p, exePath, out] {
        m_iconJobs.remove(exePath);
        p->deleteLater();
        if (QFileInfo(out).size() > 0)
            Q_EMIT iconReady(exePath, QUrl::fromLocalFile(out).toString());
    });
    p->start(QStringLiteral("sh"), {QStringLiteral("-c"), script, QStringLiteral("sh"), exePath, tmp, out});
    return {};
}

QString Compat::prettyName(const QString &exePath)
{
    QString base = QFileInfo(exePath).completeBaseName();
    base.replace(QLatin1Char('_'), QLatin1Char(' '));
    if (!base.isEmpty() && base.at(0).isLower())
        base[0] = base.at(0).toUpper();
    return base;
}

QVariantMap Compat::programForPid(qint64 pid)
{
    if (pid <= 0)
        return {};
    if (m_pidCache.contains(pid)) {
        QVariantMap m = m_pidCache.value(pid);
        if (m.value(QStringLiteral("icon")).toString().isEmpty() && !m.isEmpty())
            m.insert(QStringLiteral("icon"), exeIcon(m.value(QStringLiteral("exe")).toString()));
        return m;
    }
    QFile f(QStringLiteral("/proc/%1/cmdline").arg(pid));
    QVariantMap result;
    if (f.open(QIODevice::ReadOnly)) {
        const QList<QByteArray> args = f.readAll().split('\0');
        for (const QByteArray &a : args) {
            QString arg = QString::fromLocal8Bit(a);
            if (!arg.endsWith(QLatin1String(".exe"), Qt::CaseInsensitive))
                continue;
            // Windows-style paths: map drive letters into our prefix.
            QString unixPath = arg;
            if (arg.size() > 2 && arg.at(1) == QLatin1Char(':')) {
                unixPath = prefix() + QStringLiteral("/dosdevices/") + arg.left(2).toLower() + arg.mid(2).replace(QLatin1Char('\\'), QLatin1Char('/'));
                unixPath = QFileInfo(unixPath).canonicalFilePath().isEmpty() ? unixPath : QFileInfo(unixPath).canonicalFilePath();
            }
            const QString lower = QFileInfo(unixPath).fileName().toLower();
            if (lower == QLatin1String("start.exe") || lower == QLatin1String("wineconsole.exe") || lower == QLatin1String("explorer.exe")
                || lower == QLatin1String("services.exe") || lower == QLatin1String("winedevice.exe") || lower == QLatin1String("conhost.exe"))
                continue;
            result = {{QStringLiteral("name"), prettyName(unixPath)}, {QStringLiteral("exe"), unixPath},
                      {QStringLiteral("icon"), exeIcon(unixPath)}};
            break;
        }
    }
    m_pidCache.insert(pid, result);
    return result;
}

QStringList Compat::startMenuShortcuts() const
{
    QStringList out;
    const QString c = prefix() + QStringLiteral("/drive_c");
    QStringList roots = {c + QStringLiteral("/ProgramData/Microsoft/Windows/Start Menu/Programs")};
    const QDir users(c + QStringLiteral("/users"));
    for (const QString &u : users.entryList(QDir::Dirs | QDir::NoDotAndDotDot))
        roots << users.filePath(u) + QStringLiteral("/AppData/Roaming/Microsoft/Windows/Start Menu/Programs");
    for (const QString &root : roots) {
        QDirIterator it(root, {QStringLiteral("*.lnk")}, QDir::Files, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            const QString p = it.next();
            const QString name = QFileInfo(p).completeBaseName().toLower();
            if (name.contains(QLatin1String("uninstall")) || name.contains(QLatin1String("readme")) || name.contains(QLatin1String("help")))
                continue;
            out << p;
        }
    }
    return out;
}

QString Compat::installCommand(const QString &component) const
{
    const bool java = component == QLatin1String("java");
    auto has = [](const char *p) { return !QStandardPaths::findExecutable(QString::fromLatin1(p)).isEmpty(); };
    if (has("apt-get"))
        return java ? QStringLiteral("sudo apt-get install -y default-jre") : QStringLiteral("sudo dpkg --add-architecture i386 && sudo apt-get update && sudo apt-get install -y wine wine64 wine32 icoutils");
    if (has("dnf"))
        return java ? QStringLiteral("sudo dnf install -y java-latest-openjdk") : QStringLiteral("sudo dnf install -y wine icoutils");
    if (has("pacman"))
        return java ? QStringLiteral("sudo pacman -S --needed jre-openjdk") : QStringLiteral("sudo pacman -S --needed wine icoutils");
    if (has("zypper"))
        return java ? QStringLiteral("sudo zypper install -y java-21-openjdk") : QStringLiteral("sudo zypper install -y wine icoutils");
    return {};
}

void Compat::installRuntime(const QString &component)
{
    const QString cmd = installCommand(component);
    const QString term = Launcher::instance()->terminal();
    if (cmd.isEmpty() || term.isEmpty())
        return;
    const QString wrapped = cmd + QStringLiteral("; echo; echo Done. You can close this window.; read -r _");
    Launcher::instance()->run({term, QStringLiteral("-e"), QStringLiteral("sh"), QStringLiteral("-c"), wrapped});
    QTimer::singleShot(30000, this, &Compat::refresh);
}

void Compat::openConfiguration()
{
    if (m_wine.isEmpty())
        return;
    QProcess p;
    p.setProgram(m_wine);
    p.setArguments({QStringLiteral("winecfg")});
    p.setProcessEnvironment(environment(Launcher::instance()->clientEnvironment()));
    p.startDetached();
}
