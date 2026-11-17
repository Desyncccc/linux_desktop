// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

// File system helpers for the Explorer and desktop icons.
class Files : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString home READ home CONSTANT)
    Q_PROPERTY(QString desktop READ desktop CONSTANT)
    Q_PROPERTY(QString documents READ documents CONSTANT)
    Q_PROPERTY(QString downloads READ downloads CONSTANT)
    Q_PROPERTY(QString music READ music CONSTANT)
    Q_PROPERTY(QString pictures READ pictures CONSTANT)
    Q_PROPERTY(QString videos READ videos CONSTANT)
    Q_PROPERTY(QString trash READ trash CONSTANT)
    Q_PROPERTY(QStringList clipboard READ clipboard NOTIFY clipboardChanged)
    Q_PROPERTY(bool clipboardCut READ clipboardCut NOTIFY clipboardChanged)

public:
    static Files *create(QQmlEngine *, QJSEngine *);
    static Files *instance();

    QString home() const;
    QString desktop() const;
    QString documents() const;
    QString downloads() const;
    QString music() const;
    QString pictures() const;
    QString videos() const;
    QString trash() const;
    QStringList clipboard() const { return m_clipboard; }
    bool clipboardCut() const { return m_cut; }

    Q_INVOKABLE QString iconName(const QString &path) const;
    Q_INVOKABLE QString typeName(const QString &path) const;
    Q_INVOKABLE QString formatSize(qint64 bytes) const;
    Q_INVOKABLE bool isDir(const QString &path) const;
    Q_INVOKABLE bool exists(const QString &path) const;
    Q_INVOKABLE QString parentDir(const QString &path) const;
    Q_INVOKABLE QString fileName(const QString &path) const;
    Q_INVOKABLE QString displayName(const QString &path) const;
    Q_INVOKABLE QString toLocal(const QVariant &urlOrPath) const;
    Q_INVOKABLE QString toUrl(const QString &path) const;
    Q_INVOKABLE QString makeFolder(const QString &parent, const QString &baseName = QStringLiteral("New folder"));
    Q_INVOKABLE QString makeFile(const QString &parent, const QString &baseName = QStringLiteral("New Text Document.txt"));
    Q_INVOKABLE bool rename(const QString &path, const QString &newName);
    Q_INVOKABLE bool moveToTrash(const QStringList &paths);
    Q_INVOKABLE bool emptyTrash();
    Q_INVOKABLE int trashCount() const;
    Q_INVOKABLE void copy(const QStringList &paths);
    Q_INVOKABLE void cut(const QStringList &paths);
    Q_INVOKABLE bool paste(const QString &targetDir);
    // Drag and drop: move (or copy) files into a folder.
    Q_INVOKABLE bool transfer(const QStringList &paths, const QString &targetDir, bool copy = false);
    Q_INVOKABLE QVariantList volumes() const;
    Q_INVOKABLE QVariantMap info(const QString &path) const;
    // .desktop launcher on the desktop: returns {name, icon} or {}.
    Q_INVOKABLE QVariantMap desktopFileInfo(const QString &path) const;
    Q_INVOKABLE bool launchDesktopFile(const QString &path);
    Q_INVOKABLE bool isImage(const QString &path) const;
    Q_INVOKABLE bool isText(const QString &path) const;
    Q_INVOKABLE QString readText(const QString &path) const;
    Q_INVOKABLE bool writeText(const QString &path, const QString &text);
    Q_INVOKABLE QStringList siblingImages(const QString &path) const;
    // Visible subfolders of a folder (navigation tree, address bar menus).
    Q_INVOKABLE QVariantList subfolders(const QString &path, bool includeHidden = false) const;
    Q_INVOKABLE bool hasSubfolders(const QString &path) const;
    // Drive letter-style label for a mount point ("Local Disk (C:)").
    Q_INVOKABLE QString volumeLabel(const QString &mountPoint) const;

Q_SIGNALS:
    void clipboardChanged();
    void changed(const QString &dir);

private:
    explicit Files(QObject *parent = nullptr);
    bool transferFiles(const QStringList &sources, const QString &targetDir, bool copy);
    QStringList m_clipboard;
    bool m_cut = false;
};
