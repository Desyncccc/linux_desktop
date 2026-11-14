// SPDX-License-Identifier: GPL-3.0-or-later
#include "notifications.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QUrl>

static Notifications *s_notifications = nullptr;

Notifications::Notifications(QObject *parent)
    : QAbstractListModel(parent)
{
    if (qEnvironmentVariableIsSet("VITRUM_NO_DBUS"))
        return;
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected())
        return;
    auto *adaptor = new NotificationsAdaptor(this);
    if (!bus.registerObject(QStringLiteral("/org/freedesktop/Notifications"), adaptor,
                            QDBusConnection::ExportScriptableContents)) {
        qWarning("vitrum: could not export notification object");
        return;
    }
    m_registered = bus.registerService(QStringLiteral("org.freedesktop.Notifications"));
    if (!m_registered)
        qWarning("vitrum: another notification daemon is running; toasts from apps are disabled");
}

Notifications *Notifications::instance()
{
    if (!s_notifications)
        s_notifications = new Notifications;
    return s_notifications;
}

Notifications *Notifications::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

int Notifications::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_items.size());
}

QVariant Notifications::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_items.size())
        return {};
    const Item &it = m_items.at(index.row());
    switch (role) {
    case IdRole: return it.id;
    case AppNameRole: return it.appName;
    case AppIconRole: return it.appIcon;
    case SummaryRole: return it.summary;
    case BodyRole: return it.body;
    case ActionsRole: {
        QVariantList l;
        for (int i = 0; i + 1 < it.actions.size(); i += 2)
            l << QVariantMap{{QStringLiteral("key"), it.actions.at(i)}, {QStringLiteral("label"), it.actions.at(i + 1)}};
        return l;
    }
    case ImageRole: return it.image;
    case UrgencyRole: return it.urgency;
    case TimeRole: return it.time;
    }
    return {};
}

QHash<int, QByteArray> Notifications::roleNames() const
{
    return {{IdRole, "notificationId"}, {AppNameRole, "appName"}, {AppIconRole, "appIcon"}, {SummaryRole, "summary"},
            {BodyRole, "body"}, {ActionsRole, "actions"}, {ImageRole, "image"}, {UrgencyRole, "urgency"}, {TimeRole, "time"}};
}

int Notifications::indexOf(uint id) const
{
    for (int i = 0; i < m_items.size(); ++i)
        if (m_items.at(i).id == id)
            return i;
    return -1;
}

uint Notifications::notify(const QString &appName, uint replacesId, const QString &appIcon, const QString &summary,
                           const QString &body, const QStringList &actions, const QVariantMap &hints, int timeout)
{
    Item it;
    it.id = replacesId && indexOf(replacesId) >= 0 ? replacesId : m_nextId++;
    it.appName = appName;
    it.appIcon = appIcon;
    if (it.appIcon.isEmpty())
        it.appIcon = hints.value(QStringLiteral("desktop-entry")).toString();
    it.summary = summary;
    it.body = body;
    it.actions = actions;
    it.urgency = hints.value(QStringLiteral("urgency"), 1).toInt();
    it.transient = hints.value(QStringLiteral("transient")).toBool();
    QString image = hints.value(QStringLiteral("image-path")).toString();
    if (image.isEmpty())
        image = hints.value(QStringLiteral("image_path")).toString();
    if (image.startsWith(QLatin1Char('/')))
        image = QUrl::fromLocalFile(image).toString();
    it.image = image;
    it.timeout = timeout;
    it.time = QDateTime::currentDateTime();

    const int existing = indexOf(it.id);
    if (existing >= 0) {
        m_items[existing] = it;
        Q_EMIT dataChanged(index(existing), index(existing));
    } else {
        beginInsertRows({}, 0, 0);
        m_items.prepend(it);
        endInsertRows();
        Q_EMIT countChanged();
    }
    Q_EMIT notificationAdded(it.id, it.urgency >= 2 ? 0 : (timeout < 0 ? 6000 : timeout));
    return it.id;
}

uint Notifications::post(const QString &summary, const QString &body, const QString &icon)
{
    return notify(QStringLiteral("Vitrum"), 0, icon, summary, body, {}, {}, 5000);
}

QVariantMap Notifications::get(uint id) const
{
    const int i = indexOf(id);
    if (i < 0)
        return {};
    QVariantMap m;
    const QModelIndex idx = index(i);
    const auto roles = roleNames();
    for (auto it = roles.constBegin(); it != roles.constEnd(); ++it)
        m.insert(QString::fromLatin1(it.value()), data(idx, it.key()));
    return m;
}

void Notifications::close(uint id, uint reason)
{
    const int i = indexOf(id);
    if (i < 0)
        return;
    beginRemoveRows({}, i, i);
    m_items.removeAt(i);
    endRemoveRows();
    Q_EMIT countChanged();
    Q_EMIT notificationRemoved(id);
    Q_EMIT closed(id, reason);
}

void Notifications::dismiss(uint id) { close(id, 2); }

void Notifications::expire(uint id)
{
    const int i = indexOf(id);
    if (i >= 0 && m_items.at(i).transient)
        close(id, 1);
}

void Notifications::invokeAction(uint id, const QString &key)
{
    Q_EMIT actionInvoked(id, key);
    close(id, 2);
}

void Notifications::clearAll()
{
    const QList<Item> items = m_items;
    for (const Item &it : items)
        close(it.id, 2);
}

NotificationsAdaptor::NotificationsAdaptor(Notifications *n)
    : QObject(n)
    , m_n(n)
{
    connect(n, &Notifications::closed, this, &NotificationsAdaptor::NotificationClosed);
    connect(n, &Notifications::actionInvoked, this, &NotificationsAdaptor::ActionInvoked);
}

QStringList NotificationsAdaptor::GetCapabilities()
{
    return {QStringLiteral("body"), QStringLiteral("actions"), QStringLiteral("icon-static"), QStringLiteral("persistence")};
}

uint NotificationsAdaptor::Notify(const QString &app_name, uint replaces_id, const QString &app_icon, const QString &summary,
                                  const QString &body, const QStringList &actions, const QVariantMap &hints, int expire_timeout)
{
    return m_n->notify(app_name, replaces_id, app_icon, summary, body, actions, hints, expire_timeout);
}

void NotificationsAdaptor::CloseNotification(uint id) { m_n->close(id, 3); }

QString NotificationsAdaptor::GetServerInformation(QString &vendor, QString &version, QString &spec_version)
{
    vendor = QStringLiteral("Vitrum");
    version = QCoreApplication::applicationVersion();
    spec_version = QStringLiteral("1.2");
    return QStringLiteral("Vitrum Shell");
}
