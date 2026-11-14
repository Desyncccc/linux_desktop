// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QRect>
#include <QSize>


// Process-level state: startup options, version info, screenshots and exit.
class Session : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool windowed READ windowed CONSTANT)
    Q_PROPERTY(QSize windowSize READ windowSize CONSTANT)
    Q_PROPERTY(bool demo READ demo CONSTANT)
    Q_PROPERTY(QString demoDir READ demoDir CONSTANT)
    Q_PROPERTY(QString demoClient READ demoClient CONSTANT)
    Q_PROPERTY(QString version READ version CONSTANT)
    Q_PROPERTY(QString qtVersion READ qtVersion CONSTANT)
    Q_PROPERTY(QString platform READ platform CONSTANT)
    Q_PROPERTY(QString fontFamily READ fontFamily CONSTANT)

public:
    static Session *instance();
    static Session *create(QQmlEngine *, QJSEngine *);

    void configure(bool windowed, const QSize &size, bool demo, const QString &demoDir, const QString &demoClient);

    bool windowed() const { return m_windowed; }
    QSize windowSize() const { return m_size; }
    bool demo() const { return m_demo; }
    QString demoDir() const { return m_demoDir; }
    QString demoClient() const { return m_demoClient; }
    QString version() const;
    QString qtVersion() const;
    QString platform() const;
    QString fontFamily() const;

    Q_INVOKABLE void quit(int code = 0);
    Q_INVOKABLE void logout();
    Q_INVOKABLE bool saveScreenshot(QQuickWindow *window, const QString &path, const QRect &crop = {});
    Q_INVOKABLE QString newScreenshotPath() const;
    Q_INVOKABLE QString env(const QString &name) const;
    Q_INVOKABLE void importEnvironment();
    // Hides the shell's own cursor while a client draws its cursor surface.
    Q_INVOKABLE void setClientCursor(bool clientOwnsCursor);

    static int warningCount();
    static void installMessageHandler(bool strict);

private:
    explicit Session(QObject *parent = nullptr);
    bool m_windowed = false;
    QSize m_size;
    bool m_demo = false;
    QString m_demoDir;
    QString m_demoClient;
    bool m_cursorOverridden = false;
};
