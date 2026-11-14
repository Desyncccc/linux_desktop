// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QPointer>
#include <QQmlEngine>
#include <QSet>
#include <QWaylandCompositorExtensionTemplate>

#include "qwayland-server-server-decoration.h"

#include <QWaylandCompositor>
#include <QWaylandSurface>

// org_kde_kwin_server_decoration_manager: the decoration protocol GTK and
// Firefox speak. We always answer "server", so those apps get our frame
// instead of drawing their own title bars.
class ServerDecorations : public QWaylandCompositorExtensionTemplate<ServerDecorations>,
                          public QtWaylandServer::org_kde_kwin_server_decoration_manager
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(int revision READ revision NOTIFY revisionChanged)

public:
    static ServerDecorations *instance();
    static ServerDecorations *create(QQmlEngine *, QJSEngine *);

    void attach(QWaylandCompositor *compositor);
    void initialize() override;

    Q_INVOKABLE bool isServerDecorated(QWaylandSurface *surface) const;
    int revision() const { return m_revision; }

    void setSurfaceMode(QWaylandSurface *surface, bool server);

Q_SIGNALS:
    void revisionChanged();

protected:
    void org_kde_kwin_server_decoration_manager_bind_resource(Resource *resource) override;
    void org_kde_kwin_server_decoration_manager_create(Resource *resource, uint32_t id, struct ::wl_resource *surface) override;

private:
    ServerDecorations();
    QSet<QWaylandSurface *> m_server;
    QSet<QWaylandSurface *> m_watched;
    int m_revision = 0;
};
