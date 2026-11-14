// SPDX-License-Identifier: GPL-3.0-or-later
#include "session.h"
#include "launcher.h"

#include <QDateTime>
#include <QDir>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QCursor>
#include <QImage>
#include <QProcess>
#include <QQuickWindow>
#include <QStandardPaths>
#include <atomic>

static Session *s_session = nullptr;
static std::atomic<int> s_warnings{0};
static bool s_strict = false;
static QtMessageHandler s_prevHandler = nullptr;

static void messageHandler(QtMsgType type, const QMessageLogContext &ctx, const QString &msg)
{
    if (s_strict && type != QtDebugMsg && type != QtInfoMsg) {
        // Count QML/JS problems; benign platform chatter is ignored.
        const bool fromQml = ctx.category && (qstrcmp(ctx.category, "qml") == 0 || qstrcmp(ctx.category, "js") == 0
                                              || qstrncmp(ctx.category, "qt.qml", 6) == 0);
        if ((fromQml || msg.contains(QLatin1String(".qml:"))) && !msg.contains(QLatin1String("qt-project.org")))
            ++s_warnings;
    }
    if (s_prevHandler)
        s_prevHandler(type, ctx, msg);
}

void Session::installMessageHandler(bool strict)
{
    s_strict = strict;
    s_prevHandler = qInstallMessageHandler(messageHandler);
}

int Session::warningCount() { return s_warnings.load(); }

Session::Session(QObject *parent)
    : QObject(parent)
{
}

Session *Session::instance()
{
    if (!s_session)
        s_session = new Session;
    return s_session;
}

Session *Session::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

void Session::configure(bool windowed, const QSize &size, bool demo, const QString &demoDir, const QString &demoClient)
{
    m_windowed = windowed;
    m_size = size;
    m_demo = demo;
    m_demoDir = demoDir;
    m_demoClient = demoClient;
}

QString Session::version() const { return QCoreApplication::applicationVersion(); }
QString Session::qtVersion() const { return QString::fromLatin1(qVersion()); }
QString Session::platform() const { return QGuiApplication::platformName(); }

QString Session::fontFamily() const
{
    static const QStringList preferred = {
        QStringLiteral("Segoe UI"), QStringLiteral("Selawik"), QStringLiteral("Noto Sans"),
        QStringLiteral("Open Sans"), QStringLiteral("Cantarell"), QStringLiteral("DejaVu Sans"),
    };
    const QStringList families = QFontDatabase::families();
    for (const QString &p : preferred)
        if (families.contains(p, Qt::CaseInsensitive))
            return p;
    return QGuiApplication::font().family();
}

void Session::quit(int code)
{
    if (s_strict && code == 0 && s_warnings.load() > 0) {
        qWarning("vitrum: %d QML warning(s) during run, failing (strict mode)", s_warnings.load());
        code = 3;
    }
    QCoreApplication::exit(code);
}

void Session::logout() { quit(0); }

bool Session::saveScreenshot(QQuickWindow *window, const QString &path, const QRect &crop)
{
    if (!window)
        return false;
    QImage img = window->grabWindow();
    if (img.isNull())
        return false;
    if (crop.isValid()) {
        const qreal dpr = img.devicePixelRatio();
        img = img.copy(QRect(crop.topLeft() * dpr, crop.size() * dpr));
    }
    QDir().mkpath(QFileInfo(path).absolutePath());
    return img.save(path);
}

QString Session::newScreenshotPath() const
{
    QString pictures = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    if (pictures.isEmpty())
        pictures = QDir::homePath();
    return pictures + QStringLiteral("/Screenshots/Screenshot ")
        + QDateTime::currentDateTime().toString(QStringLiteral("yyyy-MM-dd hhmmss")) + QStringLiteral(".png");
}

QString Session::env(const QString &name) const { return qEnvironmentVariable(name.toLocal8Bit().constData()); }

void Session::importEnvironment()
{
    // Make WAYLAND_DISPLAY etc. visible to D-Bus activated services and portals.
    const QStringList vars = {QStringLiteral("WAYLAND_DISPLAY"), QStringLiteral("XDG_CURRENT_DESKTOP"), QStringLiteral("XDG_SESSION_TYPE")};
    if (!QStandardPaths::findExecutable(QStringLiteral("dbus-update-activation-environment")).isEmpty())
        QProcess::startDetached(QStringLiteral("sh"), {QStringLiteral("-c"),
            QStringLiteral("WAYLAND_DISPLAY=%1 XDG_CURRENT_DESKTOP=Vitrum XDG_SESSION_TYPE=wayland dbus-update-activation-environment --systemd %2")
                .arg(Launcher::instance()->socketName(), vars.join(QLatin1Char(' ')))});
}

void Session::setClientCursor(bool clientOwnsCursor)
{
    if (clientOwnsCursor == m_cursorOverridden)
        return;
    m_cursorOverridden = clientOwnsCursor;
    if (clientOwnsCursor)
        QGuiApplication::setOverrideCursor(QCursor(Qt::BlankCursor));
    else
        QGuiApplication::restoreOverrideCursor();
}
