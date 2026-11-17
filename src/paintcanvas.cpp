// SPDX-License-Identifier: GPL-3.0-or-later
#include "paintcanvas.h"

#include <QClipboard>
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImageReader>
#include <QImageWriter>
#include <QPainter>
#include <QQuickWindow>
#include <QRandomGenerator>
#include <QtMath>

#include <functional>

namespace {
constexpr int kHistoryLimit = 50;

QPainterPath polygonPath(const QList<QPointF> &unit, const QRectF &r)
{
    // Normalise to the unit polygon's own bounds so the shape fills the box.
    qreal minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    for (const QPointF &p : unit) {
        minX = qMin(minX, p.x()); maxX = qMax(maxX, p.x());
        minY = qMin(minY, p.y()); maxY = qMax(maxY, p.y());
    }
    const qreal sw = qMax(1e-6, maxX - minX), sh = qMax(1e-6, maxY - minY);
    QPolygonF poly;
    for (const QPointF &p : unit)
        poly << QPointF(r.left() + (p.x() - minX) / sw * r.width(), r.top() + (p.y() - minY) / sh * r.height());
    QPainterPath path;
    path.addPolygon(poly);
    path.closeSubpath();
    return path;
}

QList<QPointF> starPoints(int n, qreal inner)
{
    QList<QPointF> pts;
    for (int i = 0; i < 2 * n; ++i) {
        const qreal a = -M_PI / 2 + i * M_PI / n;
        const qreal rad = (i % 2) ? inner : 1.0;
        pts << QPointF(rad * qCos(a), rad * qSin(a));
    }
    return pts;
}

QList<QPointF> regularPoints(int n)
{
    QList<QPointF> pts;
    for (int i = 0; i < n; ++i) {
        const qreal a = -M_PI / 2 + i * 2 * M_PI / n;
        pts << QPointF(qCos(a), qSin(a));
    }
    return pts;
}

QPainterPath mapUnit(const QPainterPath &unit, const QRectF &r)
{
    QTransform t;
    t.translate(r.left(), r.top());
    t.scale(r.width(), r.height());
    return t.map(unit);
}

QImage noiseTexture(const QColor &c, int density, int alphaMin)
{
    QImage tex(32, 32, QImage::Format_ARGB32_Premultiplied);
    tex.fill(Qt::transparent);
    QRandomGenerator rng(1234);   // stable pattern so strokes join seamlessly
    for (int y = 0; y < tex.height(); ++y)
        for (int x = 0; x < tex.width(); ++x)
            if (int(rng.bounded(100)) < density) {
                QColor px = c;
                px.setAlpha(alphaMin + int(rng.bounded(256 - alphaMin)));
                tex.setPixelColor(x, y, px);
            }
    return tex;
}
} // namespace

PaintCanvas::PaintCanvas(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setOpaquePainting(false);
    setAntialiasing(false);
    newImage(800, 600);
    if (auto *cb = QGuiApplication::clipboard())
        connect(cb, &QClipboard::dataChanged, this, &PaintCanvas::clipboardChanged);
}

QImage PaintCanvas::normalized(const QImage &img)
{
    // Paint pictures are opaque: flatten any transparency onto white.
    QImage out(img.size(), QImage::Format_ARGB32_Premultiplied);
    out.fill(Qt::white);
    QPainter p(&out);
    p.drawImage(0, 0, img);
    return out;
}

void PaintCanvas::updateSize()
{
    setImplicitSize(m_image.width() * m_zoom, m_image.height() * m_zoom);
    update();
}

void PaintCanvas::setImage(const QImage &img, bool resetHistory)
{
    const QSize old = m_image.size();
    m_image = img;
    if (resetHistory) {
        m_undo.clear();
        m_redo.clear();
        Q_EMIT historyChanged();
    }
    if (old != m_image.size())
        m_layer = QImage();
    Q_EMIT imageChanged();
    updateSize();
}

void PaintCanvas::touch()
{
    setModified(true);
    update();
}

void PaintCanvas::setZoom(qreal z)
{
    z = qBound(0.125, z, 8.0);
    if (qFuzzyCompare(z, m_zoom))
        return;
    m_zoom = z;
    Q_EMIT zoomChanged();
    updateSize();
}

void PaintCanvas::setOrigin(const QPointF &o)
{
    if (m_origin == o)
        return;
    m_origin = o;
    Q_EMIT originChanged();
    update();
}

void PaintCanvas::setModified(bool m)
{
    if (m_modified == m)
        return;
    m_modified = m;
    Q_EMIT modifiedChanged();
}

void PaintCanvas::setShowGrid(bool on)
{
    if (m_showGrid == on)
        return;
    m_showGrid = on;
    Q_EMIT showGridChanged();
    update();
}

void PaintCanvas::setTransparentSelection(bool on)
{
    if (m_transparentSel == on)
        return;
    m_transparentSel = on;
    Q_EMIT transparentSelectionChanged();
    update();
}

void PaintCanvas::setSecondaryColor(const QColor &c)
{
    if (m_secondary == c)
        return;
    m_secondary = c;
    Q_EMIT secondaryColorChanged();
    if (m_floating && m_transparentSel)
        update();
}

bool PaintCanvas::clipboardHasImage() const
{
    const QClipboard *cb = QGuiApplication::clipboard();
    return cb && !cb->image().isNull();
}

// ---------------------------------------------------------------- document

void PaintCanvas::newImage(int w, int h)
{
    QImage img(qMax(1, w), qMax(1, h), QImage::Format_ARGB32_Premultiplied);
    img.fill(Qt::white);
    m_sel = QRect();
    m_selPath = QPainterPath();
    m_floating = false;
    m_float = QImage();
    m_preview.clear();
    m_ink.clear();
    Q_EMIT inkChanged();
    Q_EMIT selectionChanged();
    setImage(img, true);
    setModified(false);
}

bool PaintCanvas::load(const QString &path)
{
    QImageReader reader(path);
    reader.setAutoTransform(true);
    const QImage img = reader.read();
    if (img.isNull())
        return false;
    newImage(1, 1);
    setImage(normalized(img), true);
    setModified(false);
    return true;
}

bool PaintCanvas::save(const QString &path)
{
    QImage img = composite(true);
    const QString ext = QFileInfo(path).suffix().toLower();
    QByteArray format = "png";
    int quality = -1;
    if (ext == QLatin1String("jpg") || ext == QLatin1String("jpeg") || ext == QLatin1String("jpe")) {
        format = "jpeg";
        quality = 92;
        img = img.convertToFormat(QImage::Format_RGB888);
    } else if (ext == QLatin1String("bmp") || ext == QLatin1String("dib")) {
        format = "bmp";
        img = img.convertToFormat(QImage::Format_RGB888);
    } else if (ext == QLatin1String("tif") || ext == QLatin1String("tiff")) {
        format = "tiff";
    } else {
        img = img.convertToFormat(QImage::Format_RGB32);
    }
    QDir().mkpath(QFileInfo(path).absolutePath());
    QImageWriter writer(path, format);
    if (quality > 0)
        writer.setQuality(quality);
    if (!writer.write(img))
        return false;
    setModified(false);
    return true;
}

bool PaintCanvas::grabWindow(QQuickWindow *window)
{
    if (!window)
        return false;
    QImage img = window->grabWindow();
    if (img.isNull())
        return false;
    img.setDevicePixelRatio(1);
    newImage(1, 1);
    setImage(normalized(img), true);
    return true;
}

bool PaintCanvas::copyFrom(PaintCanvas *source, const QRect &rect, const QVariantList &freeForm)
{
    if (!source)
        return false;
    const QRect r = rect.intersected(source->m_image.rect());
    if (r.isEmpty())
        return false;
    QImage img = source->m_image.copy(r);
    if (freeForm.size() > 2) {
        QPolygonF poly;
        for (const QVariant &v : freeForm)
            poly << v.toPointF() - QPointF(r.topLeft());
        QImage masked(img.size(), QImage::Format_ARGB32_Premultiplied);
        masked.fill(Qt::white);
        QPainter p(&masked);
        p.setRenderHint(QPainter::Antialiasing);
        QPainterPath path;
        path.addPolygon(poly);
        path.closeSubpath();
        p.setClipPath(path);
        p.drawImage(0, 0, img);
        img = masked;
    }
    newImage(1, 1);
    setImage(img, true);
    setModified(true);
    return true;
}

QImage PaintCanvas::composite(bool withInk) const
{
    QImage img = m_image.copy();
    QPainter p(&img);
    if (m_floating && !m_float.isNull())
        p.drawImage(m_sel.topLeft(), floatForDraw());
    if (withInk)
        drawInk(p);
    return img;
}

QImage PaintCanvas::floatForDraw() const
{
    if (!m_transparentSel)
        return m_float;
    QImage img = m_float.convertToFormat(QImage::Format_ARGB32);
    const QRgb key = m_secondary.rgb() & 0xffffff;
    for (int y = 0; y < img.height(); ++y) {
        QRgb *line = reinterpret_cast<QRgb *>(img.scanLine(y));
        for (int x = 0; x < img.width(); ++x)
            if ((line[x] & 0xffffff) == key)
                line[x] = 0;
    }
    return img;
}

// ---------------------------------------------------------------- history

void PaintCanvas::pushUndo()
{
    m_undo.append(m_image);
    while (m_undo.size() > kHistoryLimit)
        m_undo.removeFirst();
    m_redo.clear();
    Q_EMIT historyChanged();
}

void PaintCanvas::undo()
{
    m_preview.clear();
    if (m_floating) {
        // The lift pushed a snapshot: undoing restores the picture before it.
        m_floating = false;
        m_float = QImage();
    }
    m_sel = QRect();
    m_selPath = QPainterPath();
    Q_EMIT selectionChanged();
    if (m_undo.isEmpty()) {
        update();
        return;
    }
    m_redo.append(m_image);
    setImage(m_undo.takeLast(), false);
    Q_EMIT historyChanged();
    touch();
}

void PaintCanvas::redo()
{
    if (m_redo.isEmpty())
        return;
    clearSelection();
    m_undo.append(m_image);
    setImage(m_redo.takeLast(), false);
    Q_EMIT historyChanged();
    touch();
}

// ---------------------------------------------------------------- freehand

void PaintCanvas::beginStroke(const QString &tool, const QColor &color, const QColor &other, qreal size, const QPointF &p)
{
    pushUndo();
    m_tool = tool;
    m_color = color;
    m_other = other;
    m_size = qMax<qreal>(1, size);
    m_last = p;
    m_stroking = true;
    m_layerOpacity = 1;
    if (tool == QLatin1String("marker") || tool == QLatin1String("watercolor")) {
        m_layerOpacity = tool == QLatin1String("marker") ? 0.55 : 0.45;
        m_layer = QImage(m_image.size(), QImage::Format_ARGB32_Premultiplied);
        m_layer.fill(Qt::transparent);
    }
    strokeTo(p);
}

void PaintCanvas::strokeTo(const QPointF &p)
{
    if (!m_stroking)
        return;
    const QPointF a = m_last;
    m_last = p;
    if (m_tool == QLatin1String("eraser")) {
        eraseSegment(a, p);
    } else if (m_layerOpacity < 1) {
        QPainter painter(&m_layer);
        stampSegment(painter, a, p);
    } else {
        QPainter painter(&m_image);
        stampSegment(painter, a, p);
    }
    touch();
}

void PaintCanvas::spray()
{
    if (m_stroking && m_tool == QLatin1String("airbrush"))
        strokeTo(m_last);
}

void PaintCanvas::endStroke()
{
    if (!m_stroking)
        return;
    m_stroking = false;
    if (m_layerOpacity < 1 && !m_layer.isNull()) {
        QPainter p(&m_image);
        p.setOpacity(m_layerOpacity);
        p.drawImage(0, 0, m_layer);
        p.end();
        m_layer = QImage();
    }
    m_layerOpacity = 1;
    touch();
}

void PaintCanvas::stampSegment(QPainter &p, const QPointF &a, const QPointF &b)
{
    stamp(p, m_tool, m_color, m_size, a, b);
}

void PaintCanvas::stamp(QPainter &p, const QString &t, const QColor &color, qreal s, const QPointF &a, const QPointF &b)
{
    if (t == QLatin1String("pencil")) {
        p.setRenderHint(QPainter::Antialiasing, false);
        const QPoint ia(qFloor(a.x()), qFloor(a.y())), ib(qFloor(b.x()), qFloor(b.y()));
        if (s <= 1) {
            p.setPen(QPen(color, 1));
            if (ia == ib)
                p.drawPoint(ia);
            else
                p.drawLine(ia, ib);
        } else {
            QPen pen(color, s, Qt::SolidLine, Qt::SquareCap, Qt::MiterJoin);
            p.setPen(pen);
            const QPointF off = int(s) % 2 ? QPointF(0.5, 0.5) : QPointF(0, 0);
            p.drawLine(QPointF(ia) + off, QPointF(ib) + off);
        }
        return;
    }
    p.setRenderHint(QPainter::Antialiasing, true);
    if (t == QLatin1String("calligraphy1") || t == QLatin1String("calligraphy2")) {
        const qreal h = s / 2;
        const QPointF nib = t == QLatin1String("calligraphy1") ? QPointF(h, -h) : QPointF(h, h);
        QPolygonF quad;
        quad << a + nib << b + nib << b - nib << a - nib;
        p.setPen(QPen(color, 1));
        p.setBrush(color);
        p.drawPolygon(quad);
        return;
    }
    if (t == QLatin1String("airbrush")) {
        auto *rng = QRandomGenerator::global();
        const qreal radius = s;
        const int dots = int(radius * 2.2) + 4;
        p.setRenderHint(QPainter::Antialiasing, false);
        p.setPen(QPen(color, 1));
        const qreal len = QLineF(a, b).length();
        const int steps = qMax(1, int(len / qMax<qreal>(1, radius / 2)));
        for (int k = 0; k < steps; ++k) {
            const QPointF c = a + (b - a) * (steps == 1 ? 1.0 : qreal(k + 1) / steps);
            for (int i = 0; i < dots; ++i) {
                const qreal ang = rng->generateDouble() * 2 * M_PI;
                const qreal rr = radius * qSqrt(rng->generateDouble());
                p.drawPoint(QPointF(c.x() + rr * qCos(ang), c.y() + rr * qSin(ang)).toPoint());
            }
        }
        return;
    }
    QBrush brush(color);
    Qt::PenCapStyle cap = Qt::RoundCap;
    qreal width = s;
    if (t == QLatin1String("oil")) {
        brush = styleBrush(QStringLiteral("oil"), color);
        width = s * 1.4;
    } else if (t == QLatin1String("crayon")) {
        brush = styleBrush(QStringLiteral("crayon"), color);
        cap = Qt::SquareCap;
        width = s * 1.3;
    } else if (t == QLatin1String("pencil2")) {   // natural pencil
        brush = styleBrush(QStringLiteral("pencil"), color);
        width = qMax<qreal>(1, s * 0.6);
    } else if (t == QLatin1String("marker")) {
        cap = Qt::SquareCap;
        width = s * 1.6;
    } else if (t == QLatin1String("watercolor")) {
        width = s * 1.6;
    }
    p.setPen(QPen(brush, width, Qt::SolidLine, cap, Qt::RoundJoin));
    if (a == b)
        p.drawPoint(a);
    else
        p.drawLine(a, b);
}

void PaintCanvas::eraseSegment(const QPointF &a, const QPointF &b)
{
    // m_color is the colour painted (colour 2). With an opaque m_other (right
    // button) only pixels of that colour (colour 1) are replaced.
    const int s = qMax(1, int(m_size));
    const int steps = qMax(1, int(QLineF(a, b).length()));
    const bool selective = m_other.isValid() && m_other.alpha() > 0;
    const QRgb from = m_other.rgb() | 0xff000000;
    const QRgb to = m_color.rgb() | 0xff000000;
    for (int i = 0; i <= steps; ++i) {
        const QPointF c = a + (b - a) * (qreal(i) / steps);
        const QRect r = QRect(qFloor(c.x()) - s / 2, qFloor(c.y()) - s / 2, s, s).intersected(m_image.rect());
        for (int y = r.top(); y <= r.bottom(); ++y) {
            QRgb *line = reinterpret_cast<QRgb *>(m_image.scanLine(y));
            for (int x = r.left(); x <= r.right(); ++x)
                if (!selective || line[x] == from)
                    line[x] = to;
        }
    }
}

void PaintCanvas::floodFill(int x, int y, const QColor &color)
{
    if (!m_image.rect().contains(x, y))
        return;
    QImage &img = m_image;
    const QRgb target = img.pixel(x, y);
    const QRgb fill = color.rgb() | 0xff000000;
    if (target == fill)
        return;
    pushUndo();
    const int w = img.width(), h = img.height();
    QList<QPoint> stack;
    stack.append(QPoint(x, y));
    while (!stack.isEmpty()) {
        QPoint pt = stack.takeLast();
        int px = pt.x();
        const int py = pt.y();
        QRgb *line = reinterpret_cast<QRgb *>(img.scanLine(py));
        if (line[px] != target)
            continue;
        while (px > 0 && line[px - 1] == target)
            --px;
        bool upOpen = false, downOpen = false;
        QRgb *up = py > 0 ? reinterpret_cast<QRgb *>(img.scanLine(py - 1)) : nullptr;
        QRgb *down = py < h - 1 ? reinterpret_cast<QRgb *>(img.scanLine(py + 1)) : nullptr;
        while (px < w && line[px] == target) {
            line[px] = fill;
            if (up) {
                if (up[px] == target) {
                    if (!upOpen) { stack.append(QPoint(px, py - 1)); upOpen = true; }
                } else {
                    upOpen = false;
                }
            }
            if (down) {
                if (down[px] == target) {
                    if (!downOpen) { stack.append(QPoint(px, py + 1)); downOpen = true; }
                } else {
                    downOpen = false;
                }
            }
            ++px;
        }
    }
    touch();
}

QColor PaintCanvas::pixelAt(int x, int y) const
{
    const QImage img = composite(false);
    if (!img.rect().contains(x, y))
        return QColor();
    return QColor(img.pixel(x, y));
}

// ---------------------------------------------------------------- shapes

QBrush PaintCanvas::styleBrush(const QString &style, const QColor &c)
{
    if (style == QLatin1String("marker")) {
        QColor m = c;
        m.setAlpha(140);
        return QBrush(m);
    }
    if (style == QLatin1String("watercolor")) {
        QColor m = c;
        m.setAlpha(90);
        return QBrush(m);
    }
    if (style == QLatin1String("crayon"))
        return QBrush(noiseTexture(c, 62, 200));
    if (style == QLatin1String("pencil"))
        return QBrush(noiseTexture(c, 45, 120));
    if (style == QLatin1String("oil"))
        return QBrush(noiseTexture(c, 100, 150));
    return QBrush(c);
}

QPainterPath PaintCanvas::shapePath(const QString &s, const QRectF &r, const QList<QPointF> &pts)
{
    QPainterPath path;
    if (s == QLatin1String("line")) {
        if (pts.size() >= 2) {
            path.moveTo(pts[0]);
            path.lineTo(pts[1]);
        } else {
            path.moveTo(r.topLeft());
            path.lineTo(r.bottomRight());
        }
    } else if (s == QLatin1String("curve")) {
        if (pts.size() >= 4) {
            path.moveTo(pts[0]);
            path.cubicTo(pts[2], pts[3], pts[1]);
        } else {
            path.moveTo(r.bottomLeft());
            path.cubicTo(QPointF(r.left() + r.width() * 0.3, r.top() - r.height() * 0.4),
                         QPointF(r.left() + r.width() * 0.7, r.bottom() + r.height() * 0.4), r.topRight());
        }
    } else if (s == QLatin1String("polygon")) {
        if (pts.size() >= 2) {
            path.moveTo(pts[0]);
            for (int i = 1; i < pts.size(); ++i)
                path.lineTo(pts[i]);
        }
    } else if (s == QLatin1String("oval")) {
        path.addEllipse(r);
    } else if (s == QLatin1String("rectangle")) {
        path.addRect(r);
    } else if (s == QLatin1String("roundrect")) {
        const qreal rad = qMin(qAbs(r.width()), qAbs(r.height())) * 0.18;
        path.addRoundedRect(r, rad, rad);
    } else if (s == QLatin1String("triangle")) {
        path = polygonPath({{0.5, 0}, {1, 1}, {0, 1}}, r);
    } else if (s == QLatin1String("righttriangle")) {
        path = polygonPath({{0, 0}, {1, 1}, {0, 1}}, r);
    } else if (s == QLatin1String("diamond")) {
        path = polygonPath({{0.5, 0}, {1, 0.5}, {0.5, 1}, {0, 0.5}}, r);
    } else if (s == QLatin1String("pentagon")) {
        path = polygonPath(regularPoints(5), r);
    } else if (s == QLatin1String("hexagon")) {
        path = polygonPath({{0.25, 0}, {0.75, 0}, {1, 0.5}, {0.75, 1}, {0.25, 1}, {0, 0.5}}, r);
    } else if (s.startsWith(QLatin1String("arrow"))) {
        const QList<QPointF> u = {{0, 0.25}, {0.55, 0.25}, {0.55, 0}, {1, 0.5}, {0.55, 1}, {0.55, 0.75}, {0, 0.75}};
        QList<QPointF> m;
        for (const QPointF &p : u) {
            if (s == QLatin1String("arrowleft")) m << QPointF(1 - p.x(), p.y());
            else if (s == QLatin1String("arrowdown")) m << QPointF(p.y(), p.x());
            else if (s == QLatin1String("arrowup")) m << QPointF(p.y(), 1 - p.x());
            else m << p;
        }
        path = polygonPath(m, r);
    } else if (s == QLatin1String("star4")) {
        path = polygonPath(starPoints(4, 0.32), r);
    } else if (s == QLatin1String("star5")) {
        path = polygonPath(starPoints(5, 0.4), r);
    } else if (s == QLatin1String("star6")) {
        path = polygonPath(starPoints(6, 0.55), r);
    } else if (s == QLatin1String("heart")) {
        QPainterPath u;
        u.moveTo(0.5, 0.27);
        u.cubicTo(0.45, 0.02, 0.0, -0.02, 0.0, 0.3);
        u.cubicTo(0.0, 0.55, 0.3, 0.72, 0.5, 1.0);
        u.cubicTo(0.7, 0.72, 1.0, 0.55, 1.0, 0.3);
        u.cubicTo(1.0, -0.02, 0.55, 0.02, 0.5, 0.27);
        u.closeSubpath();
        path = mapUnit(u, r);
    } else if (s == QLatin1String("lightning")) {
        path = polygonPath({{0.38, 0}, {0.62, 0.25}, {0.54, 0.29}, {0.8, 0.52}, {0.72, 0.56}, {1, 1},
                            {0.48, 0.64}, {0.57, 0.6}, {0.22, 0.42}, {0.32, 0.37}, {0, 0.14}}, r);
    } else if (s == QLatin1String("calloutrect")) {
        QPainterPath u;
        u.addRoundedRect(QRectF(0, 0, 1, 0.74), 0.08, 0.1);
        QPainterPath tail;
        tail.addPolygon(QPolygonF({QPointF(0.18, 0.7), QPointF(0.1, 1.0), QPointF(0.38, 0.7)}));
        tail.closeSubpath();
        path = mapUnit(u.united(tail).simplified(), r);
    } else if (s == QLatin1String("calloutoval")) {
        QPainterPath u;
        u.addEllipse(QRectF(0, 0, 1, 0.78));
        QPainterPath tail;
        tail.addPolygon(QPolygonF({QPointF(0.2, 0.62), QPointF(0.08, 1.0), QPointF(0.42, 0.74)}));
        tail.closeSubpath();
        path = mapUnit(u.united(tail).simplified(), r);
    } else if (s == QLatin1String("cloud")) {
        QPainterPath u;
        u.addEllipse(QRectF(0.05, 0.25, 0.35, 0.38));
        u.addEllipse(QRectF(0.22, 0.05, 0.36, 0.42));
        u.addEllipse(QRectF(0.5, 0.1, 0.38, 0.4));
        u.addEllipse(QRectF(0.6, 0.32, 0.36, 0.36));
        u.addEllipse(QRectF(0.3, 0.38, 0.42, 0.36));
        u.addEllipse(QRectF(0.12, 0.42, 0.3, 0.3));
        u.setFillRule(Qt::WindingFill);
        QPainterPath dots;
        dots.addEllipse(QRectF(0.1, 0.8, 0.08, 0.08));
        dots.addEllipse(QRectF(0.03, 0.92, 0.05, 0.05));
        path = mapUnit(u.simplified().united(dots), r);
    } else {
        path.addRect(r);
    }
    return path;
}

void PaintCanvas::drawShape(QPainter &p, const QVariantMap &spec) const
{
    const QString shape = spec.value(QStringLiteral("shape")).toString();
    const QPointF a(spec.value(QStringLiteral("x1")).toReal(), spec.value(QStringLiteral("y1")).toReal());
    const QPointF b(spec.value(QStringLiteral("x2")).toReal(), spec.value(QStringLiteral("y2")).toReal());
    QList<QPointF> pts;
    const QVariantList vpts = spec.value(QStringLiteral("points")).toList();
    for (const QVariant &v : vpts)
        pts << v.toPointF();
    if (pts.isEmpty() && shape == QLatin1String("line"))
        pts << a << b;
    QRectF r = QRectF(a, b).normalized();
    const qreal width = spec.value(QStringLiteral("width"), 1).toReal();
    const QString outline = spec.value(QStringLiteral("outline"), QStringLiteral("solid")).toString();
    const QString fill = spec.value(QStringLiteral("fill"), QStringLiteral("none")).toString();
    const QColor color = spec.value(QStringLiteral("color")).value<QColor>();
    const QColor fillColor = spec.value(QStringLiteral("fillColor")).value<QColor>();
    const bool closedPoly = shape == QLatin1String("polygon") && spec.value(QStringLiteral("closed")).toBool();
    const bool open = shape == QLatin1String("line") || shape == QLatin1String("curve")
                      || (shape == QLatin1String("polygon") && !closedPoly);
    // Keep a 1px outline crisp by drawing on pixel centres.
    if (int(qRound(width)) % 2 == 1 && !open)
        r.translate(0.5, 0.5);
    QPainterPath path = shapePath(shape, r, pts);
    if (closedPoly)
        path.closeSubpath();
    if ((open || shape == QLatin1String("polygon")) && int(qRound(width)) % 2 == 1)
        path.translate(0.5, 0.5);
    p.save();
    p.setRenderHint(QPainter::Antialiasing, true);
    if (!open && fill != QLatin1String("none")) {
        p.setPen(Qt::NoPen);
        p.setBrush(styleBrush(fill, fillColor));
        p.drawPath(path);
    }
    if (open || outline != QLatin1String("none")) {
        p.setBrush(Qt::NoBrush);
        QPen pen(styleBrush(open ? (outline == QLatin1String("none") ? QStringLiteral("solid") : outline) : outline, color),
                 width, Qt::SolidLine, open ? Qt::RoundCap : Qt::SquareCap, Qt::MiterJoin);
        if (shape == QLatin1String("roundrect") || shape == QLatin1String("oval") || shape == QLatin1String("heart")
            || shape == QLatin1String("cloud") || shape == QLatin1String("calloutoval") || shape == QLatin1String("calloutrect"))
            pen.setJoinStyle(Qt::RoundJoin);
        p.setPen(pen);
        p.drawPath(path);
    }
    p.restore();
}

void PaintCanvas::setPreview(const QVariantMap &spec)
{
    m_preview = spec;
    update();
}

void PaintCanvas::clearPreview()
{
    m_preview.clear();
    update();
}

void PaintCanvas::commitPreview()
{
    if (m_preview.isEmpty())
        return;
    pushUndo();
    QPainter p(&m_image);
    drawShape(p, m_preview);
    p.end();
    m_preview.clear();
    touch();
}

void PaintCanvas::drawText(const QRectF &rect, const QString &text, const QVariantMap &font,
                           const QColor &color, bool opaque, const QColor &background)
{
    if (text.isEmpty() && !opaque)
        return;
    pushUndo();
    QPainter p(&m_image);
    p.setRenderHint(QPainter::TextAntialiasing, true);
    p.setRenderHint(QPainter::Antialiasing, true);
    if (opaque)
        p.fillRect(rect, background);
    QFont f(font.value(QStringLiteral("family")).toString());
    f.setPixelSize(qMax(1, font.value(QStringLiteral("pixelSize"), 16).toInt()));
    f.setBold(font.value(QStringLiteral("bold")).toBool());
    f.setItalic(font.value(QStringLiteral("italic")).toBool());
    f.setUnderline(font.value(QStringLiteral("underline")).toBool());
    f.setStrikeOut(font.value(QStringLiteral("strikeout")).toBool());
    p.setFont(f);
    p.setPen(color);
    const qreal pad = font.value(QStringLiteral("padding"), 0).toReal();
    p.drawText(rect.adjusted(pad, pad, -pad, -pad), Qt::TextWordWrap | Qt::AlignLeft | Qt::AlignTop, text);
    p.end();
    touch();
}

// ---------------------------------------------------------------- selection

void PaintCanvas::setSelection(const QRect &r)
{
    clearSelection();
    m_sel = r.normalized().intersected(m_image.rect());
    m_selPath = QPainterPath();
    Q_EMIT selectionChanged();
    update();
}

void PaintCanvas::setFreeFormSelection(const QVariantList &points)
{
    clearSelection();
    if (points.size() < 3)
        return;
    QPolygonF poly;
    for (const QVariant &v : points)
        poly << v.toPointF();
    QPainterPath path;
    path.addPolygon(poly);
    path.closeSubpath();
    m_sel = path.boundingRect().toAlignedRect().intersected(m_image.rect());
    m_selPath = m_sel.isValid() ? path : QPainterPath();
    Q_EMIT selectionChanged();
    update();
}

void PaintCanvas::selectAll()
{
    setSelection(m_image.rect());
}

void PaintCanvas::clearSelection()
{
    if (m_floating) {
        QPainter p(&m_image);
        p.drawImage(m_sel.topLeft(), floatForDraw());
        p.end();
        m_floating = false;
        m_float = QImage();
        touch();
    }
    if (m_sel.isValid() || !m_selPath.isEmpty()) {
        m_sel = QRect();
        m_selPath = QPainterPath();
        Q_EMIT selectionChanged();
        update();
    }
}

void PaintCanvas::liftSelection()
{
    if (m_floating || !m_sel.isValid())
        return;
    pushUndo();
    m_float = QImage(m_sel.size(), QImage::Format_ARGB32_Premultiplied);
    m_float.fill(Qt::transparent);
    QPainter fp(&m_float);
    if (!m_selPath.isEmpty())
        fp.setClipPath(m_selPath.translated(-m_sel.topLeft()));
    fp.drawImage(QPoint(0, 0), m_image, m_sel);
    fp.end();
    QPainter p(&m_image);
    if (!m_selPath.isEmpty())
        p.fillPath(m_selPath, m_secondary);
    else
        p.fillRect(m_sel, m_secondary);
    p.end();
    m_floating = true;
    Q_EMIT selectionChanged();
    touch();
}

void PaintCanvas::moveSelectionTo(int x, int y)
{
    if (!m_sel.isValid())
        return;
    if (!m_floating)
        liftSelection();
    m_sel.moveTopLeft(QPoint(x, y));
    Q_EMIT selectionChanged();
    touch();
}

void PaintCanvas::copySelection()
{
    QClipboard *cb = QGuiApplication::clipboard();
    if (!cb)
        return;
    if (m_floating) {
        cb->setImage(normalized(floatForDraw()));
    } else if (m_sel.isValid()) {
        QImage img = m_image.copy(m_sel);
        if (!m_selPath.isEmpty()) {
            QImage masked(img.size(), QImage::Format_ARGB32_Premultiplied);
            masked.fill(Qt::white);
            QPainter p(&masked);
            p.setClipPath(m_selPath.translated(-m_sel.topLeft()));
            p.drawImage(0, 0, img);
            p.end();
            img = masked;
        }
        cb->setImage(img);
    } else {
        cb->setImage(composite(true));
    }
}

void PaintCanvas::cutSelection()
{
    copySelection();
    deleteSelection();
}

void PaintCanvas::deleteSelection()
{
    if (!m_sel.isValid())
        return;
    if (!m_floating)
        liftSelection();
    m_floating = false;
    m_float = QImage();
    m_sel = QRect();
    m_selPath = QPainterPath();
    Q_EMIT selectionChanged();
    touch();
}

bool PaintCanvas::paste(int x, int y)
{
    const QClipboard *cb = QGuiApplication::clipboard();
    if (!cb)
        return false;
    const QImage img = cb->image();
    if (img.isNull())
        return false;
    clearSelection();
    pushUndo();
    const QPoint at(qMax(0, x), qMax(0, y));
    const QSize need(at.x() + img.width(), at.y() + img.height());
    if (need.width() > m_image.width() || need.height() > m_image.height()) {
        QImage bigger(qMax(need.width(), m_image.width()), qMax(need.height(), m_image.height()),
                      QImage::Format_ARGB32_Premultiplied);
        bigger.fill(m_secondary);
        QPainter p(&bigger);
        p.drawImage(0, 0, m_image);
        p.end();
        setImage(bigger, false);
    }
    m_float = normalized(img);
    m_sel = QRect(at, img.size());
    m_selPath = QPainterPath();
    m_floating = true;
    Q_EMIT selectionChanged();
    touch();
    return true;
}

bool PaintCanvas::pasteFrom(const QString &path, int x, int y)
{
    QImageReader reader(path);
    reader.setAutoTransform(true);
    const QImage img = reader.read();
    if (img.isNull())
        return false;
    if (QClipboard *cb = QGuiApplication::clipboard())
        cb->setImage(img);
    return paste(x, y);
}

void PaintCanvas::cropToSelection()
{
    if (!m_sel.isValid())
        return;
    QImage img;
    if (m_floating) {
        img = normalized(floatForDraw());
        pushUndo();
    } else {
        pushUndo();
        img = m_image.copy(m_sel);
        if (!m_selPath.isEmpty()) {
            QImage masked(img.size(), QImage::Format_ARGB32_Premultiplied);
            masked.fill(m_secondary);
            QPainter p(&masked);
            p.setClipPath(m_selPath.translated(-m_sel.topLeft()));
            p.drawImage(0, 0, img);
            p.end();
            img = masked;
        }
    }
    m_floating = false;
    m_float = QImage();
    m_sel = QRect();
    m_selPath = QPainterPath();
    Q_EMIT selectionChanged();
    setImage(img, false);
    touch();
}

void PaintCanvas::applyToTarget(const std::function<QImage(const QImage &)> &fn)
{
    if (m_sel.isValid()) {
        if (!m_floating)
            liftSelection();
        m_float = fn(m_float);
        m_sel.setSize(m_float.size());
        Q_EMIT selectionChanged();
        touch();
        return;
    }
    pushUndo();
    setImage(fn(m_image).convertToFormat(QImage::Format_ARGB32_Premultiplied), false);
    touch();
}

void PaintCanvas::invertColors()
{
    applyToTarget([](const QImage &src) {
        QImage img = src.convertToFormat(QImage::Format_ARGB32);
        img.invertPixels(QImage::InvertRgb);
        return img.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    });
}

void PaintCanvas::blackAndWhite()
{
    clearSelection();
    applyToTarget([](const QImage &src) {
        QImage img = src.convertToFormat(QImage::Format_ARGB32);
        for (int y = 0; y < img.height(); ++y) {
            QRgb *line = reinterpret_cast<QRgb *>(img.scanLine(y));
            for (int x = 0; x < img.width(); ++x)
                line[x] = qGray(line[x]) < 128 ? 0xff000000 : 0xffffffff;
        }
        return img.convertToFormat(QImage::Format_ARGB32_Premultiplied);
    });
}

void PaintCanvas::rotate(int degrees)
{
    applyToTarget([degrees](const QImage &src) {
        QTransform t;
        t.rotate(degrees);
        return src.transformed(t, Qt::FastTransformation);
    });
}

void PaintCanvas::flip(bool horizontal)
{
    applyToTarget([horizontal](const QImage &src) {
#if QT_VERSION >= QT_VERSION_CHECK(6, 9, 0)
        return src.flipped(horizontal ? Qt::Horizontal : Qt::Vertical);
#else
        return src.mirrored(horizontal, !horizontal);
#endif
    });
}

void PaintCanvas::resizeImage(int w, int h)
{
    w = qBound(1, w, 20000);
    h = qBound(1, h, 20000);
    applyToTarget([w, h](const QImage &src) {
        return src.scaled(w, h, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
    });
}

void PaintCanvas::skew(qreal hDegrees, qreal vDegrees)
{
    if (qFuzzyIsNull(hDegrees) && qFuzzyIsNull(vDegrees))
        return;
    const QColor bg = m_secondary;
    const bool sel = m_sel.isValid();
    applyToTarget([=](const QImage &src) {
        QTransform t;
        t.shear(qTan(qDegreesToRadians(hDegrees)), qTan(qDegreesToRadians(vDegrees)));
        const QRect bounds = t.mapRect(QRectF(src.rect())).toAlignedRect();
        QImage out(bounds.size(), QImage::Format_ARGB32_Premultiplied);
        out.fill(sel ? QColor(Qt::transparent) : bg);
        QPainter p(&out);
        p.setRenderHint(QPainter::SmoothPixmapTransform);
        p.translate(-bounds.topLeft());
        p.setTransform(t, true);
        p.drawImage(0, 0, src);
        return out;
    });
}

void PaintCanvas::resizeCanvas(int w, int h)
{
    w = qBound(1, w, 20000);
    h = qBound(1, h, 20000);
    if (w == m_image.width() && h == m_image.height())
        return;
    clearSelection();
    pushUndo();
    QImage img(w, h, QImage::Format_ARGB32_Premultiplied);
    img.fill(m_secondary);
    QPainter p(&img);
    p.drawImage(0, 0, m_image);
    p.end();
    setImage(img, false);
    touch();
}

// ---------------------------------------------------------------- ink

void PaintCanvas::inkBegin(const QPointF &p, const QColor &color, qreal width, bool highlighter)
{
    Ink ink;
    ink.path.moveTo(p);
    ink.path.lineTo(p + QPointF(0.01, 0.01));
    ink.color = color;
    ink.width = width;
    ink.highlighter = highlighter;
    m_ink.append(ink);
    m_inking = true;
    Q_EMIT inkChanged();
    touch();
}

void PaintCanvas::inkTo(const QPointF &p)
{
    if (!m_inking || m_ink.isEmpty())
        return;
    m_ink.last().path.lineTo(p);
    update();
}

void PaintCanvas::inkEnd()
{
    m_inking = false;
}

bool PaintCanvas::inkEraseAt(const QPointF &p, qreal radius)
{
    QPainterPath probe;
    probe.addEllipse(p, radius, radius);
    for (int i = m_ink.size() - 1; i >= 0; --i) {
        QPainterPathStroker stroker;
        stroker.setWidth(m_ink[i].width);
        if (stroker.createStroke(m_ink[i].path).intersects(probe)) {
            m_ink.removeAt(i);
            Q_EMIT inkChanged();
            touch();
            return true;
        }
    }
    return false;
}

void PaintCanvas::inkClear()
{
    if (m_ink.isEmpty())
        return;
    m_ink.clear();
    Q_EMIT inkChanged();
    update();
}

void PaintCanvas::drawInk(QPainter &p) const
{
    for (const Ink &ink : m_ink) {
        p.save();
        p.setRenderHint(QPainter::Antialiasing, true);
        if (ink.highlighter) {
            p.setCompositionMode(QPainter::CompositionMode_Multiply);
            p.setPen(QPen(ink.color, ink.width, Qt::SolidLine, Qt::SquareCap, Qt::RoundJoin));
        } else {
            p.setPen(QPen(ink.color, ink.width, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        }
        p.setBrush(Qt::NoBrush);
        p.drawPath(ink.path);
        p.restore();
    }
}

void PaintCanvas::copyImage()
{
    if (QClipboard *cb = QGuiApplication::clipboard())
        cb->setImage(composite(true));
}

// ---------------------------------------------------------------- rendering

void PaintCanvas::paint(QPainter *p)
{
    const qreal z = m_zoom;
    p->translate(-m_origin);
    // Only the part of the picture this item covers.
    const QRectF view(m_origin, QSizeF(width(), height()));
    const QRectF src(view.left() / z, view.top() / z, view.width() / z, view.height() / z);
    p->save();
    p->setRenderHint(QPainter::SmoothPixmapTransform, z < 1);
    if (z >= 1) {
        // Whole source pixels, so zoomed pixels stay square and aligned.
        const QRect s = src.toAlignedRect().intersected(m_image.rect());
        p->drawImage(QRectF(s.x() * z, s.y() * z, s.width() * z, s.height() * z), m_image, s);
    } else {
        p->drawImage(QRectF(0, 0, m_image.width() * z, m_image.height() * z), m_image);
    }
    p->setClipRect(view);
    p->scale(z, z);
    if (!m_layer.isNull() && m_stroking) {
        p->setOpacity(m_layerOpacity);
        p->drawImage(0, 0, m_layer);
        p->setOpacity(1);
    }
    if (m_floating && !m_float.isNull())
        p->drawImage(m_sel.topLeft(), floatForDraw());
    if (!m_preview.isEmpty())
        drawShape(*p, m_preview);
    drawInk(*p);
    p->restore();

    if (m_showGrid) {
        int step = 1;
        while (step * z < 8)
            step *= 2;
        p->setPen(QColor(0, 0, 0, 38));
        const int x0 = qMax(step, int(src.left() / step) * step), x1 = qMin(m_image.width(), int(src.right()) + 1);
        const int y0 = qMax(step, int(src.top() / step) * step), y1 = qMin(m_image.height(), int(src.bottom()) + 1);
        for (int x = x0; x < x1; x += step)
            p->drawLine(QPointF(x * z + 0.5, view.top()), QPointF(x * z + 0.5, view.bottom()));
        for (int y = y0; y < y1; y += step)
            p->drawLine(QPointF(view.left(), y * z + 0.5), QPointF(view.right(), y * z + 0.5));
    }
}

// ---------------------------------------------------------------- glyphs

PaintGlyph::PaintGlyph(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
}

void PaintGlyph::setShape(const QString &s) { if (m_shape != s) { m_shape = s; Q_EMIT changed(); update(); } }
void PaintGlyph::setBrush(const QString &b) { if (m_brush != b) { m_brush = b; Q_EMIT changed(); update(); } }
void PaintGlyph::setColor(const QColor &c) { if (m_color != c) { m_color = c; Q_EMIT changed(); update(); } }
void PaintGlyph::setLineWidth(qreal w) { if (!qFuzzyCompare(m_lineWidth, w)) { m_lineWidth = w; Q_EMIT changed(); update(); } }

void PaintGlyph::paint(QPainter *p)
{
    const QRectF box(0, 0, width(), height());
    p->setRenderHint(QPainter::Antialiasing, true);
    if (!m_shape.isEmpty()) {
        const QRectF r = box.adjusted(1.5, 1.5, -1.5, -1.5);
        QList<QPointF> pts;
        if (m_shape == QLatin1String("line"))
            pts << r.topLeft() << r.bottomRight();
        else if (m_shape == QLatin1String("polygon"))
            pts << QPointF(r.left() + r.width() * 0.1, r.top()) << QPointF(r.right(), r.top() + r.height() * 0.35)
                << QPointF(r.left() + r.width() * 0.75, r.bottom()) << QPointF(r.left(), r.top() + r.height() * 0.7)
                << QPointF(r.left() + r.width() * 0.1, r.top());
        QPainterPath path = PaintCanvas::shapePath(m_shape, r, pts);
        p->setPen(QPen(m_color, m_lineWidth, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p->setBrush(Qt::NoBrush);
        p->drawPath(path);
        return;
    }
    if (!m_brush.isEmpty()) {
        // An S-shaped sample stroke.
        QImage img(int(width()), int(height()), QImage::Format_ARGB32_Premultiplied);
        img.fill(Qt::transparent);
        QPainter ip(&img);
        const qreal w = width(), h = height();
        QPointF last(w * 0.12, h * 0.75);
        const qreal size = m_brush == QLatin1String("airbrush") ? 6 : (m_brush == QLatin1String("pencil2") ? 3 : 4);
        for (int i = 1; i <= 24; ++i) {
            const qreal t = i / 24.0;
            const QPointF pt(w * (0.12 + 0.76 * t), h * (0.5 + 0.28 * qCos(t * M_PI * 1.6)));
            PaintCanvas::stamp(ip, m_brush, m_color, size, last, pt);
            last = pt;
        }
        ip.end();
        if (m_brush == QLatin1String("marker"))
            p->setOpacity(0.55);
        else if (m_brush == QLatin1String("watercolor"))
            p->setOpacity(0.45);
        p->drawImage(0, 0, img);
    }
}

// ---------------------------------------------------------------- marquee

PaintMarquee::PaintMarquee(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
}

void PaintMarquee::setPoints(const QVariantList &p) { m_points = p; Q_EMIT changed(); update(); }
void PaintMarquee::setClosed(bool c) { if (m_closed != c) { m_closed = c; Q_EMIT changed(); update(); } }
void PaintMarquee::setDashed(bool d) { if (m_dashed != d) { m_dashed = d; Q_EMIT changed(); update(); } }
void PaintMarquee::setColor(const QColor &c) { if (m_color != c) { m_color = c; Q_EMIT changed(); update(); } }
void PaintMarquee::setLineWidth(qreal w) { if (!qFuzzyCompare(m_lineWidth, w)) { m_lineWidth = w; Q_EMIT changed(); update(); } }

void PaintMarquee::paint(QPainter *p)
{
    QPainterPath path;
    if (m_points.size() >= 2) {
        path.moveTo(m_points.first().toPointF());
        for (int i = 1; i < m_points.size(); ++i)
            path.lineTo(m_points[i].toPointF());
        if (m_closed)
            path.closeSubpath();
        p->setRenderHint(QPainter::Antialiasing, !m_dashed);
    } else if (m_points.isEmpty()) {
        const qreal h = m_lineWidth / 2;
        path.addRect(QRectF(h, h, width() - m_lineWidth, height() - m_lineWidth));
    } else {
        return;
    }
    if (m_dashed) {
        p->setPen(QPen(Qt::white, m_lineWidth));
        p->drawPath(path);
        QPen pen(m_color, m_lineWidth, Qt::CustomDashLine, Qt::FlatCap);
        pen.setDashPattern({4, 4});
        p->setPen(pen);
        p->drawPath(path);
    } else {
        p->setPen(QPen(m_color, m_lineWidth, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        p->drawPath(path);
    }
}
