// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QQmlEngine>
#include <QVariantMap>

class NotificationsAdaptor;

// org.freedesktop.Notifications server. The model holds the notification history
// shown in the Action Center; newly arrived ones are announced for toasts.
class Notifications : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(bool registered READ registered CONSTANT)

public:
    struct Item {
        uint id = 0;
        QString appName;
        QString appIcon;
        QString summary;
        QString body;
        QStringList actions;
        QString image;
        int urgency = 1;
        int timeout = -1;
        bool transient = false;
        QDateTime time;
    };

    enum Roles { IdRole = Qt::UserRole + 1, AppNameRole, AppIconRole, SummaryRole, BodyRole, ActionsRole, ImageRole, UrgencyRole, TimeRole };

    static Notifications *instance();
    static Notifications *create(QQmlEngine *, QJSEngine *);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return int(m_items.size()); }
    bool registered() const { return m_registered; }

    // Called by the D-Bus adaptor.
    uint notify(const QString &appName, uint replacesId, const QString &appIcon, const QString &summary,
                const QString &body, const QStringList &actions, const QVariantMap &hints, int timeout);

    Q_INVOKABLE QVariantMap get(uint id) const;
    Q_INVOKABLE void dismiss(uint id);           // user closed it (reason 2)
    Q_INVOKABLE void expire(uint id);            // toast timed out; keep in history
    Q_INVOKABLE void invokeAction(uint id, const QString &key);
    Q_INVOKABLE void clearAll();
    // Shell-internal notifications (e.g. "Screenshot saved").
    Q_INVOKABLE uint post(const QString &summary, const QString &body, const QString &icon = {});
    void close(uint id, uint reason);

Q_SIGNALS:
    void countChanged();
    void notificationAdded(uint id, int timeout);
    void notificationRemoved(uint id);
    void closed(uint id, uint reason);
    void actionInvoked(uint id, const QString &key);

private:
    explicit Notifications(QObject *parent = nullptr);
    int indexOf(uint id) const;
    QList<Item> m_items;
    uint m_nextId = 1;
    bool m_registered = false;
};

class NotificationsAdaptor : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")

public:
    explicit NotificationsAdaptor(Notifications *n);

public Q_SLOTS:
    Q_SCRIPTABLE QStringList GetCapabilities();
    Q_SCRIPTABLE uint Notify(const QString &app_name, uint replaces_id, const QString &app_icon, const QString &summary,
                             const QString &body, const QStringList &actions, const QVariantMap &hints, int expire_timeout);
    Q_SCRIPTABLE void CloseNotification(uint id);
    Q_SCRIPTABLE QString GetServerInformation(QString &vendor, QString &version, QString &spec_version);

Q_SIGNALS:
    Q_SCRIPTABLE void NotificationClosed(uint id, uint reason);
    Q_SCRIPTABLE void ActionInvoked(uint id, const QString &action_key);

private:
    Notifications *m_n;
};
