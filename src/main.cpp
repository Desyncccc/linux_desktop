// SPDX-License-Identifier: GPL-3.0-or-later
#include "appmodel.h"
#include "compat.h"
#include "iconprovider.h"
#include "keyfilter.h"
#include "launcher.h"
#include "notifications.h"
#include "prefs.h"
#include "serverdecoration.h"
#include "session.h"

#include <QWaylandCompositor>

#include <QCommandLineParser>
#include <QQmlExtensionPlugin>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QQuickWindow>

Q_IMPORT_QML_PLUGIN(Vitrum_CorePlugin)

int main(int argc, char *argv[])
{
    // Defaults for running as a real session on DRM/KMS.
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM") && qEnvironmentVariableIsEmpty("WAYLAND_DISPLAY")
        && qEnvironmentVariableIsEmpty("DISPLAY")) {
        qputenv("QT_QPA_PLATFORM", "eglfs");
        if (qEnvironmentVariableIsEmpty("QT_QPA_EGLFS_INTEGRATION"))
            qputenv("QT_QPA_EGLFS_INTEGRATION", "eglfs_kms");
        qputenv("QT_QPA_EGLFS_ALWAYS_SET_MODE", "1");
    }
    // Wayland clients need our shared GL context for texture sharing.
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    qputenv("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1"); // if nested in a Wayland host
    qputenv("XDG_CURRENT_DESKTOP", "Vitrum");

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("vitrum"));
    QGuiApplication::setApplicationDisplayName(QStringLiteral("Vitrum"));
    QGuiApplication::setOrganizationName(QStringLiteral("Vitrum"));
    QGuiApplication::setApplicationVersion(QStringLiteral(VITRUM_VERSION));

    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Vitrum desktop shell and Wayland compositor"));
    parser.addHelpOption();
    parser.addVersionOption();
    QCommandLineOption windowedOpt({QStringLiteral("w"), QStringLiteral("windowed")},
                                   QStringLiteral("Run nested in a window of the given size (e.g. 1366x768)."),
                                   QStringLiteral("WxH"));
    QCommandLineOption demoOpt(QStringLiteral("demo"),
                               QStringLiteral("Run the scripted UI tour, write screenshots to DIR and exit."),
                               QStringLiteral("DIR"));
    QCommandLineOption clientOpt(QStringLiteral("demo-client"),
                                 QStringLiteral("Command to launch as a real Wayland client during the demo."),
                                 QStringLiteral("CMD"));
    QCommandLineOption strictOpt(QStringLiteral("strict"), QStringLiteral("Exit with an error if QML emitted warnings."));
    parser.addOptions({windowedOpt, demoOpt, clientOpt, strictOpt});
    parser.process(app);

    Session::installMessageHandler(parser.isSet(strictOpt));

    QSize size;
    bool windowed = parser.isSet(windowedOpt) || parser.isSet(demoOpt);
    if (windowed) {
        const QStringList parts = (parser.isSet(windowedOpt) ? parser.value(windowedOpt) : QStringLiteral("1366x768"))
                                      .split(QLatin1Char('x'));
        size = parts.size() == 2 ? QSize(parts[0].toInt(), parts[1].toInt()) : QSize(1366, 768);
        if (size.isEmpty())
            size = QSize(1366, 768);
    }
    Session::instance()->configure(windowed, size, parser.isSet(demoOpt), parser.value(demoOpt), parser.value(clientOpt));

    Prefs::instance()->seedDefaults();
    IconProvider::setupTheme(Prefs::instance()->iconTheme());
    app.installEventFilter(KeyFilter::instance());
    Notifications::instance();

    QQuickStyle::setStyle(QStringLiteral("Basic"));

    QQmlApplicationEngine engine;
    engine.addImportPath(QStringLiteral("qrc:/qt/qml"));
    engine.addImageProvider(QStringLiteral("icon"), new IconProvider);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(2); },
                     Qt::QueuedConnection);
    engine.load(QUrl(QStringLiteral("qrc:/qt/qml/Vitrum/qml/Main.qml")));
    if (engine.rootObjects().isEmpty())
        return 2;
    if (auto *compositor = qobject_cast<QWaylandCompositor *>(engine.rootObjects().first()))
        ServerDecorations::instance()->attach(compositor);

    if (!Session::instance()->demo()) {
        Session::instance()->importEnvironment();
        Launcher::instance()->runAutostart();
        Compat::instance()->prepare();
    }
    return app.exec();
}
