// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include "desktopentry.h"

#include <QObject>
#include <QProcessEnvironment>
#include <QQmlEngine>

// Starts client processes with an environment pointing at our Wayland socket.
class Launcher : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString socketName READ socketName CONSTANT)
    Q_PROPERTY(QString terminal READ terminal CONSTANT)

public:
    static Launcher *instance();
    static Launcher *create(QQmlEngine *, QJSEngine *);

    QString socketName() const { return m_socketName; }
    QString terminal() const;
    QProcessEnvironment clientEnvironment() const;

    bool launchEntry(const DesktopEntry &entry, const QStringList &files = {});
    Q_INVOKABLE bool run(const QStringList &args, const QString &workingDir = {});
    // Run dialog semantics: a URL, path or command line.
    Q_INVOKABLE bool runCommand(const QString &commandLine);
    Q_INVOKABLE bool openPath(const QString &pathOrUrl);
    // Opens a document/program. Returns "" on success or an error code
    // ("missing-windows", "missing-java", "failed").
    Q_INVOKABLE QString openFile(const QString &path, const QStringList &args = {});
    Q_INVOKABLE bool openTerminal(const QString &workingDir = {});
    Q_INVOKABLE bool commandExists(const QString &program) const;
    Q_INVOKABLE void runAutostart();
    static QString appLogPath();
    static void appendToAppLog(const QString &line);

private:
    explicit Launcher(QObject *parent = nullptr);
    static QString pickSocketName();
    QString m_socketName;
};
