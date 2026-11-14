// SPDX-License-Identifier: GPL-3.0-or-later
#include "launcher.h"
#include "appmodel.h"
#include "compat.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>
#include <QUrl>

static Launcher *s_launcher = nullptr;

Launcher::Launcher(QObject *parent)
    : QObject(parent)
    , m_socketName(pickSocketName())
{
}

Launcher *Launcher::instance()
{
    if (!s_launcher)
        s_launcher = new Launcher;
    return s_launcher;
}

Launcher *Launcher::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

QString Launcher::pickSocketName()
{
    const QString forced = qEnvironmentVariable("VITRUM_SOCKET");
    if (!forced.isEmpty())
        return forced;
    QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (runtime.isEmpty())
        runtime = QDir::tempPath();
    for (int i = 0; i < 32; ++i) {
        const QString name = QStringLiteral("wayland-%1").arg(i);
        if (!QFileInfo::exists(runtime + QLatin1Char('/') + name)
            && !QFileInfo::exists(runtime + QLatin1Char('/') + name + QStringLiteral(".lock")))
            return name;
    }
    return QStringLiteral("wayland-vitrum");
}

QProcessEnvironment Launcher::clientEnvironment() const
{
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert(QStringLiteral("WAYLAND_DISPLAY"), m_socketName);
    env.insert(QStringLiteral("XDG_SESSION_TYPE"), QStringLiteral("wayland"));
    env.insert(QStringLiteral("XDG_CURRENT_DESKTOP"), QStringLiteral("Vitrum"));
    env.insert(QStringLiteral("XDG_SESSION_DESKTOP"), QStringLiteral("vitrum"));
    env.insert(QStringLiteral("QT_QPA_PLATFORM"), QStringLiteral("wayland;xcb"));
    env.insert(QStringLiteral("GDK_BACKEND"), QStringLiteral("wayland,x11"));
    env.insert(QStringLiteral("SDL_VIDEODRIVER"), QStringLiteral("wayland,x11"));
    env.insert(QStringLiteral("CLUTTER_BACKEND"), QStringLiteral("wayland"));
    env.insert(QStringLiteral("MOZ_ENABLE_WAYLAND"), QStringLiteral("1"));
    env.insert(QStringLiteral("ELECTRON_OZONE_PLATFORM_HINT"), QStringLiteral("wayland"));
    env.insert(QStringLiteral("_JAVA_AWT_WM_NONREPARENTING"), QStringLiteral("1"));
    // Ask Qt clients to let us draw the (Aero) frame.
    env.insert(QStringLiteral("QT_WAYLAND_DISABLE_WINDOWDECORATION"), QStringLiteral("0"));
    env.insert(QStringLiteral("GTK_CSD"), QStringLiteral("0"));
    env.insert(QStringLiteral("MOZ_GTK_TITLEBAR_DECORATION"), QStringLiteral("system"));
    env.remove(QStringLiteral("QT_QUICK_BACKEND"));
    env.remove(QStringLiteral("QT_QPA_EGLFS_INTEGRATION"));
    env.remove(QStringLiteral("QT_XCB_GL_INTEGRATION"));
    // When running nested inside another session, don't let apps escape to the host.
    if (!qEnvironmentVariableIsSet("VITRUM_KEEP_HOST_DISPLAY"))
        env.remove(QStringLiteral("DISPLAY"));
    return env;
}

QString Launcher::terminal() const
{
    static const QStringList candidates = {
        QStringLiteral("x-terminal-emulator"), QStringLiteral("foot"), QStringLiteral("kitty"),
        QStringLiteral("alacritty"), QStringLiteral("wezterm"), QStringLiteral("konsole"),
        QStringLiteral("gnome-terminal"), QStringLiteral("kgx"), QStringLiteral("xfce4-terminal"),
        QStringLiteral("qterminal"), QStringLiteral("lxterminal"), QStringLiteral("weston-terminal"),
        QStringLiteral("xterm"),
    };
    const QString pref = qEnvironmentVariable("TERMINAL");
    if (!pref.isEmpty() && commandExists(pref))
        return pref;
    for (const QString &c : candidates)
        if (commandExists(c))
            return c;
    return {};
}

bool Launcher::commandExists(const QString &program) const
{
    if (program.contains(QLatin1Char('/')))
        return QFileInfo(program).isExecutable();
    return !QStandardPaths::findExecutable(program).isEmpty();
}

bool Launcher::run(const QStringList &args, const QString &workingDir)
{
    if (args.isEmpty())
        return false;
    QProcess p;
    p.setProgram(args.first());
    p.setArguments(args.mid(1));
    p.setProcessEnvironment(clientEnvironment());
    p.setWorkingDirectory(workingDir.isEmpty() ? QDir::homePath() : workingDir);
    p.setStandardInputFile(QProcess::nullDevice());
    // Keep apps' output in a session log so failed launches can be diagnosed.
    const QString log = appLogPath();
    if (!qEnvironmentVariableIsSet("VITRUM_CLIENT_OUTPUT")) {
        p.setStandardOutputFile(log, QIODevice::Append);
        p.setStandardErrorFile(log, QIODevice::Append);
    }
    appendToAppLog(QStringLiteral("== launching: ") + args.join(QLatin1Char(' ')));
    qint64 pid = 0;
    const bool ok = p.startDetached(&pid);
    if (!ok) {
        qWarning("vitrum: failed to start %s", qPrintable(args.join(QLatin1Char(' '))));
        appendToAppLog(QStringLiteral("== failed to start (program not found or not executable)"));
    }
    return ok;
}

QString Launcher::appLogPath()
{
    QString dir = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (dir.isEmpty())
        dir = QDir::tempPath();
    return dir + QStringLiteral("/vitrum-apps.log");
}

void Launcher::appendToAppLog(const QString &line)
{
    QFile f(appLogPath());
    if (f.open(QIODevice::WriteOnly | QIODevice::Append))
        f.write((QDateTime::currentDateTime().toString(QStringLiteral("hh:mm:ss ")) + line + QLatin1Char('\n')).toUtf8());
}

bool Launcher::launchEntry(const DesktopEntry &entry, const QStringList &files)
{
    QStringList args = entry.execArgs(files);
    if (args.isEmpty())
        return false;
    if (entry.terminal()) {
        const QString term = terminal();
        if (term.isEmpty())
            return false;
        args.prepend(QStringLiteral("-e"));
        args.prepend(term);
    }
    return run(args, entry.workingDirectory());
}

QString Launcher::openFile(const QString &path, const QStringList &args)
{
    if (Compat::kindForPath(path) != Compat::NotWindows)
        return Compat::instance()->open(path, args);
    if (QFileInfo(path).isExecutable() && !QFileInfo(path).isDir() && args.isEmpty() && !path.endsWith(QLatin1String(".desktop"))) {
        // Native programs and scripts run directly, like double-clicking an .exe.
        QFile f(path);
        if (f.open(QIODevice::ReadOnly)) {
            const QByteArray head = f.read(4);
            if (head.startsWith("#!") || head == QByteArray("\x7f" "ELF", 4))
                return run({path}, QFileInfo(path).absolutePath()) ? QString() : QStringLiteral("failed");
        }
    }
    return openPath(path) ? QString() : QStringLiteral("failed");
}

bool Launcher::openPath(const QString &pathOrUrl)
{
    if (pathOrUrl.isEmpty())
        return false;
    if (!pathOrUrl.contains(QLatin1String("://")) && Compat::kindForPath(pathOrUrl) != Compat::NotWindows)
        return Compat::instance()->open(pathOrUrl).isEmpty();
    return run({QStringLiteral("xdg-open"), pathOrUrl});
}

bool Launcher::openTerminal(const QString &workingDir)
{
    const QString term = terminal();
    return !term.isEmpty() && run({term}, workingDir);
}

bool Launcher::runCommand(const QString &commandLine)
{
    QString cmd = commandLine.trimmed();
    if (cmd.isEmpty())
        return false;

    // Desktop id or application name typed into Run.
    AppModel *apps = AppModel::instance();
    QString id = cmd.endsWith(QLatin1String(".desktop")) ? cmd : cmd + QStringLiteral(".desktop");
    if (apps->entry(id))
        return apps->launch(id);

    if (cmd.startsWith(QLatin1Char('~')))
        cmd.replace(0, 1, QDir::homePath());
    const QUrl url(cmd);
    if (url.isValid() && !url.scheme().isEmpty() && url.scheme().size() > 1 && !QFileInfo::exists(cmd))
        return openPath(cmd);
    const QFileInfo fi(cmd);
    if (fi.exists() && (fi.isDir() || !fi.isExecutable() || Compat::kindForPath(cmd) != Compat::NotWindows))
        return openFile(fi.absoluteFilePath()).isEmpty();

    QStringList args = QProcess::splitCommand(cmd);
    // "setup.exe /S" style: Windows program plus arguments.
    if (!args.isEmpty() && Compat::kindForPath(args.first()) != Compat::NotWindows) {
        QString exe = args.first();
        if (exe.startsWith(QLatin1Char('~')))
            exe.replace(0, 1, QDir::homePath());
        if (QFileInfo::exists(exe))
            return Compat::instance()->open(QFileInfo(exe).absoluteFilePath(), args.mid(1)).isEmpty();
        // Bare program names like "notepad.exe" run inside the Windows environment.
        if (Compat::instance()->windowsAvailable() && exe.endsWith(QLatin1String(".exe"), Qt::CaseInsensitive)) {
            QProcess p;
            p.setProgram(QStringLiteral("wine"));
            p.setArguments(args);
            p.setProcessEnvironment(Compat::instance()->environment(clientEnvironment()));
            return p.startDetached();
        }
    }
    if (args.isEmpty() || !commandExists(args.first()))
        return false;
    return run(args);
}

void Launcher::runAutostart()
{
    if (qEnvironmentVariableIsSet("VITRUM_NO_AUTOSTART"))
        return;
    for (const DesktopEntry &e : AppModel::autostartEntries())
        launchEntry(e);
}
