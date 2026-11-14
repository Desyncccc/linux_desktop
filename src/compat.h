// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QHash>
#include <QObject>
#include <QProcessEnvironment>
#include <QQmlEngine>
#include <QSet>
#include <QVariantMap>

// "Windows app support": runs .exe/.msi/.bat/.cmd/.lnk/.reg files through a
// private, pre-configured Windows runtime (Wine) and .jar files through Java,
// without exposing the underlying tools to the user (no Wine menus, dialogs,
// console noise or branding).
class Compat : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool windowsAvailable READ windowsAvailable NOTIFY availabilityChanged)
    Q_PROPERTY(bool javaAvailable READ javaAvailable NOTIFY availabilityChanged)
    Q_PROPERTY(bool preparing READ preparing NOTIFY preparingChanged)
    Q_PROPERTY(QString prefix READ prefix CONSTANT)
    Q_PROPERTY(QString runtimeVersion READ runtimeVersion NOTIFY availabilityChanged)

public:
    static Compat *instance();
    static Compat *create(QQmlEngine *, QJSEngine *);

    enum Kind { NotWindows, WindowsExe, WindowsInstaller, WindowsBatch, WindowsShortcut, WindowsRegistry, WindowsScript, JavaArchive };
    Q_ENUM(Kind)

    static Kind kindForPath(const QString &path);
    // Command line used to open `path`, or empty if not a handled type / runtime missing.
    QStringList commandFor(const QString &path) const;
    QProcessEnvironment environment(const QProcessEnvironment &base) const;

    bool windowsAvailable() const { return !m_wine.isEmpty(); }
    bool javaAvailable() const { return !m_java.isEmpty(); }
    bool preparing() const { return m_preparing; }
    QString prefix() const;
    QString runtimeVersion() const { return m_version; }

    // Returns "" when started, "unsupported" if not a compat type, or
    // "missing-windows" / "missing-java" if the runtime is not installed.
    Q_INVOKABLE QString open(const QString &path, const QStringList &args = {});
    Q_INVOKABLE bool isCompatFile(const QString &path) const { return kindForPath(path) != NotWindows; }
    Q_INVOKABLE QString typeName(const QString &path) const;
    // Icon extracted from an .exe (cached PNG url), or "" (extraction runs async).
    Q_INVOKABLE QString exeIcon(const QString &exePath);
    // Identity of a Windows program from a client pid: {name, exe, icon} or {}.
    Q_INVOKABLE QVariantMap programForPid(qint64 pid);
    Q_INVOKABLE QString installCommand(const QString &component) const;
    Q_INVOKABLE void installRuntime(const QString &component);
    Q_INVOKABLE void openConfiguration();
    Q_INVOKABLE void prepare();
    Q_INVOKABLE void refresh();
    // Start-menu shortcuts (.lnk) created by Windows installers in our prefix.
    QStringList startMenuShortcuts() const;
    static QString prettyName(const QString &exePath);

Q_SIGNALS:
    void availabilityChanged();
    void preparingChanged();
    void iconReady(const QString &exePath, const QString &iconUrl);
    void programsChanged();

private:
    explicit Compat(QObject *parent = nullptr);
    QString m_wine;
    QString m_java;
    QString m_version;
    bool m_preparing = false;
    QSet<QString> m_iconJobs;
    QHash<qint64, QVariantMap> m_pidCache;
};
