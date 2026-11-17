// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QColor>
#include <QImage>
#include <QList>
#include <QPainterPath>
#include <QPointer>
#include <QQmlEngine>
#include <QQuickPaintedItem>
#include <QRect>
#include <QVariant>

#include <QQuickWindow>

// Raster image editor surface used by Paint and the Snipping Tool's mark-up
// view. Holds the picture, an undo history, a floating selection, a live
// shape preview and (for snips) a vector ink layer. All coordinates passed
// in are image pixels; the item is drawn at `zoom`.
class PaintCanvas : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int imageWidth READ imageWidth NOTIFY imageChanged)
    Q_PROPERTY(int imageHeight READ imageHeight NOTIFY imageChanged)
    Q_PROPERTY(qreal zoom READ zoom WRITE setZoom NOTIFY zoomChanged)
    Q_PROPERTY(bool modified READ modified WRITE setModified NOTIFY modifiedChanged)
    Q_PROPERTY(bool canUndo READ canUndo NOTIFY historyChanged)
    Q_PROPERTY(bool canRedo READ canRedo NOTIFY historyChanged)
    Q_PROPERTY(bool showGrid READ showGrid WRITE setShowGrid NOTIFY showGridChanged)
    Q_PROPERTY(QRect selection READ selection NOTIFY selectionChanged)
    Q_PROPERTY(bool hasSelection READ hasSelection NOTIFY selectionChanged)
    Q_PROPERTY(bool floating READ floating NOTIFY selectionChanged)
    Q_PROPERTY(bool transparentSelection READ transparentSelection WRITE setTransparentSelection NOTIFY transparentSelectionChanged)
    Q_PROPERTY(QColor secondaryColor READ secondaryColor WRITE setSecondaryColor NOTIFY secondaryColorChanged)
    Q_PROPERTY(bool clipboardHasImage READ clipboardHasImage NOTIFY clipboardChanged)
    Q_PROPERTY(bool hasInk READ hasInk NOTIFY inkChanged)
    // Offset of this item within the zoomed picture, for views that only
    // cover the visible part of a large canvas.
    Q_PROPERTY(QPointF origin READ origin WRITE setOrigin NOTIFY originChanged)

public:
    explicit PaintCanvas(QQuickItem *parent = nullptr);

    void paint(QPainter *painter) override;

    int imageWidth() const { return m_image.width(); }
    int imageHeight() const { return m_image.height(); }
    qreal zoom() const { return m_zoom; }
    void setZoom(qreal z);
    bool modified() const { return m_modified; }
    void setModified(bool m);
    bool canUndo() const { return !m_undo.isEmpty(); }
    bool canRedo() const { return !m_redo.isEmpty(); }
    bool showGrid() const { return m_showGrid; }
    void setShowGrid(bool on);
    QRect selection() const { return m_sel; }
    bool hasSelection() const { return m_sel.isValid(); }
    bool floating() const { return m_floating; }
    bool transparentSelection() const { return m_transparentSel; }
    void setTransparentSelection(bool on);
    QColor secondaryColor() const { return m_secondary; }
    void setSecondaryColor(const QColor &c);
    bool clipboardHasImage() const;
    bool hasInk() const { return !m_ink.isEmpty(); }
    QPointF origin() const { return m_origin; }
    void setOrigin(const QPointF &o);

    // ---- document
    Q_INVOKABLE void newImage(int w, int h);
    Q_INVOKABLE bool load(const QString &path);
    Q_INVOKABLE bool save(const QString &path);
    Q_INVOKABLE bool grabWindow(QQuickWindow *window);
    Q_INVOKABLE bool copyFrom(PaintCanvas *source, const QRect &rect, const QVariantList &freeForm = {});

    // ---- history
    Q_INVOKABLE void pushUndo();
    Q_INVOKABLE void undo();
    Q_INVOKABLE void redo();

    // ---- freehand tools: pencil, brush styles, eraser, airbrush
    Q_INVOKABLE void beginStroke(const QString &tool, const QColor &color, const QColor &other, qreal size, const QPointF &p);
    Q_INVOKABLE void strokeTo(const QPointF &p);
    Q_INVOKABLE void spray();
    Q_INVOKABLE void endStroke();
    Q_INVOKABLE void floodFill(int x, int y, const QColor &color);
    Q_INVOKABLE QColor pixelAt(int x, int y) const;

    // ---- shapes: spec { shape, x1, y1, x2, y2, points, outline, fill, color, fillColor, width }
    Q_INVOKABLE void setPreview(const QVariantMap &spec);
    Q_INVOKABLE void clearPreview();
    Q_INVOKABLE void commitPreview();
    Q_INVOKABLE void drawText(const QRectF &rect, const QString &text, const QVariantMap &font,
                              const QColor &color, bool opaque, const QColor &background);

    // ---- selection
    Q_INVOKABLE void setSelection(const QRect &r);
    Q_INVOKABLE void setFreeFormSelection(const QVariantList &points);
    Q_INVOKABLE void selectAll();
    Q_INVOKABLE void clearSelection();   // drops the selection, stamping a floating one
    Q_INVOKABLE void liftSelection();
    Q_INVOKABLE void moveSelectionTo(int x, int y);
    Q_INVOKABLE void copySelection();
    Q_INVOKABLE void cutSelection();
    Q_INVOKABLE void deleteSelection();
    Q_INVOKABLE bool paste(int x, int y);
    Q_INVOKABLE bool pasteFrom(const QString &path, int x, int y);
    Q_INVOKABLE void cropToSelection();
    Q_INVOKABLE void invertColors();
    Q_INVOKABLE void blackAndWhite();

    // ---- whole image (or the selection, when there is one)
    Q_INVOKABLE void rotate(int degrees);
    Q_INVOKABLE void flip(bool horizontal);
    Q_INVOKABLE void resizeImage(int w, int h);
    Q_INVOKABLE void skew(qreal hDegrees, qreal vDegrees);
    Q_INVOKABLE void resizeCanvas(int w, int h);

    // ---- ink layer (Snipping Tool mark-up)
    Q_INVOKABLE void inkBegin(const QPointF &p, const QColor &color, qreal width, bool highlighter);
    Q_INVOKABLE void inkTo(const QPointF &p);
    Q_INVOKABLE void inkEnd();
    Q_INVOKABLE bool inkEraseAt(const QPointF &p, qreal radius);
    Q_INVOKABLE void inkClear();
    Q_INVOKABLE void copyImage();

    // Shared with the ribbon gallery glyphs.
    static QPainterPath shapePath(const QString &shape, const QRectF &r, const QList<QPointF> &pts);
    static void stamp(QPainter &p, const QString &tool, const QColor &color, qreal size, const QPointF &a, const QPointF &b);

Q_SIGNALS:
    void imageChanged();
    void zoomChanged();
    void modifiedChanged();
    void historyChanged();
    void showGridChanged();
    void selectionChanged();
    void transparentSelectionChanged();
    void secondaryColorChanged();
    void clipboardChanged();
    void inkChanged();
    void originChanged();

private:
    struct Ink {
        QPainterPath path;
        QColor color;
        qreal width = 2;
        bool highlighter = false;
    };

    void setImage(const QImage &img, bool resetHistory);
    void touch();
    void updateSize();
    QImage composite(bool withInk) const;
    QImage floatForDraw() const;
    void stampSegment(QPainter &p, const QPointF &a, const QPointF &b);
    void eraseSegment(const QPointF &a, const QPointF &b);
    void drawShape(QPainter &p, const QVariantMap &spec) const;
    void drawInk(QPainter &p) const;
    void applyToTarget(const std::function<QImage(const QImage &)> &fn);
    static QBrush styleBrush(const QString &style, const QColor &c);
    static QImage normalized(const QImage &img);

    QImage m_image;
    QList<QImage> m_undo;
    QList<QImage> m_redo;
    qreal m_zoom = 1;
    QPointF m_origin;
    bool m_modified = false;
    bool m_showGrid = false;

    // selection
    QRect m_sel;
    QPainterPath m_selPath;  // free-form outline in image coordinates (empty for rectangles)
    bool m_floating = false;
    QImage m_float;
    bool m_transparentSel = false;
    QColor m_secondary = Qt::white;

    // current stroke
    QString m_tool;
    QColor m_color;
    QColor m_other;
    qreal m_size = 1;
    QPointF m_last;
    bool m_stroking = false;
    QImage m_layer;          // translucent brushes accumulate here
    qreal m_layerOpacity = 1;

    // shape preview
    QVariantMap m_preview;

    // ink
    QList<Ink> m_ink;
    bool m_inking = false;
};

// Gallery thumbnail for a Paint shape or brush style.
class PaintGlyph : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString shape READ shape WRITE setShape NOTIFY changed)
    Q_PROPERTY(QString brush READ brush WRITE setBrush NOTIFY changed)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY changed)
    Q_PROPERTY(qreal lineWidth READ lineWidth WRITE setLineWidth NOTIFY changed)

public:
    explicit PaintGlyph(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;

    QString shape() const { return m_shape; }
    void setShape(const QString &s);
    QString brush() const { return m_brush; }
    void setBrush(const QString &b);
    QColor color() const { return m_color; }
    void setColor(const QColor &c);
    qreal lineWidth() const { return m_lineWidth; }
    void setLineWidth(qreal w);

Q_SIGNALS:
    void changed();

private:
    QString m_shape;
    QString m_brush;
    QColor m_color = QColor(0x1e, 0x39, 0x5b);
    qreal m_lineWidth = 1;
};

// Dashed ("marching ants") outline of its own rectangle, or of `points`
// when given. Solid when `dashed` is false.
class PaintMarquee : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QVariantList points READ points WRITE setPoints NOTIFY changed)
    Q_PROPERTY(bool closed READ closed WRITE setClosed NOTIFY changed)
    Q_PROPERTY(bool dashed READ dashed WRITE setDashed NOTIFY changed)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY changed)
    Q_PROPERTY(qreal lineWidth READ lineWidth WRITE setLineWidth NOTIFY changed)

public:
    explicit PaintMarquee(QQuickItem *parent = nullptr);
    void paint(QPainter *painter) override;

    QVariantList points() const { return m_points; }
    void setPoints(const QVariantList &p);
    bool closed() const { return m_closed; }
    void setClosed(bool c);
    bool dashed() const { return m_dashed; }
    void setDashed(bool d);
    QColor color() const { return m_color; }
    void setColor(const QColor &c);
    qreal lineWidth() const { return m_lineWidth; }
    void setLineWidth(qreal w);

Q_SIGNALS:
    void changed();

private:
    QVariantList m_points;
    bool m_closed = false;
    bool m_dashed = true;
    QColor m_color = Qt::black;
    qreal m_lineWidth = 1;
};
