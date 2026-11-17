// SPDX-License-Identifier: GPL-3.0-or-later
#include "serverdecoration.h"

#include <QWaylandCompositor>
#include <QWaylandSurface>

namespace {
class Decoration : public QObject, public QtWaylandServer::org_kde_kwin_server_decoration
{
public:
    Decoration(ServerDecorations *mgr, wl_client *client, uint32_t id, int version, QWaylandSurface *surface)
        : org_kde_kwin_server_decoration(client, int(id), version)
        , m_mgr(mgr)
        , m_surface(surface)
    {
        if (surface)
            QObject::connect(surface, &QObject::destroyed, this, [this] { m_surface = nullptr; });
        send_mode(mode_Server);
        if (m_surface)
            m_mgr->setSurfaceMode(m_surface, true);
    }

protected:
    void org_kde_kwin_server_decoration_request_mode(Resource *, uint32_t) override
    {
        // Whatever the client prefers, we draw the frame.
        send_mode(mode_Server);
        if (m_surface)
            m_mgr->setSurfaceMode(m_surface, true);
    }
    void org_kde_kwin_server_decoration_release(Resource *resource) override { wl_resource_destroy(resource->handle); }
    void org_kde_kwin_server_decoration_destroy_resource(Resource *) override
    {
        if (m_surface && m_mgr)
            m_mgr->setSurfaceMode(m_surface, false);
        delete this;
    }

private:
    QPointer<ServerDecorations> m_mgr;
    QPointer<QWaylandSurface> m_surface;
};
} // namespace

static ServerDecorations *s_instance = nullptr;

ServerDecorations::ServerDecorations() = default;

ServerDecorations *ServerDecorations::instance()
{
    if (!s_instance)
        s_instance = new ServerDecorations;
    return s_instance;
}

ServerDecorations *ServerDecorations::create(QQmlEngine *, QJSEngine *)
{
    QQmlEngine::setObjectOwnership(instance(), QQmlEngine::CppOwnership);
    return instance();
}

void ServerDecorations::attach(QWaylandCompositor *compositor)
{
    setExtensionContainer(compositor);
    initialize();
}

void ServerDecorations::initialize()
{
    QWaylandCompositorExtensionTemplate::initialize();
    auto *compositor = static_cast<QWaylandCompositor *>(extensionContainer());
    if (compositor && compositor->display())
        init(compositor->display(), 1);
}

bool ServerDecorations::isServerDecorated(QWaylandSurface *surface) const
{
    return surface && m_server.contains(surface);
}

void ServerDecorations::setSurfaceMode(QWaylandSurface *surface, bool server)
{
    const bool had = m_server.contains(surface);
    if (had == server)
        return;
    if (server) {
        m_server.insert(surface);
        if (!m_watched.contains(surface)) {
            m_watched.insert(surface);
            connect(surface, &QObject::destroyed, this, [this, surface] {
                m_server.remove(surface);
                m_watched.remove(surface);
            });
        }
    } else {
        m_server.remove(surface);
    }
    ++m_revision;
    Q_EMIT revisionChanged();
}

void ServerDecorations::org_kde_kwin_server_decoration_manager_bind_resource(Resource *resource)
{
    send_default_mode(resource->handle, mode_Server);
}

void ServerDecorations::org_kde_kwin_server_decoration_manager_create(Resource *resource, uint32_t id, struct ::wl_resource *surface)
{
    new Decoration(this, resource->client(), id, resource->version(), QWaylandSurface::fromResource(surface));
}
