/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwincurrentcursor.h"
#include "compositor.h"
#include "core/graphicsbufferview.h"
#include "cursor.h"
#include "cursorsource.h"
#include "kwinvr_logging.h"
#include "wayland/surface.h"
#include "workspace.h"
#include <QQuickWindow>
#include <QSGImageNode>
#include <core/output.h>

#include "kwincompat.h"

using namespace KWin;

KwinCurrentCursor::KwinCurrentCursor()
{
    connect(Cursors::self(), &Cursors::currentCursorChanged, this, &KwinCurrentCursor::update);
    update();
}

QSGTexture *KwinCurrentCursor::makeTexture()
{
    auto [img, hotspot] = getCursorImage();
    setCursorParams(img, hotspot);
    return !img.isNull() ? window()->createTextureFromImage(img) : nullptr;
}

std::pair<QImage, QPointF> KwinCurrentCursor::getCursorImage(bool copy)
{
    auto cur = Cursors::self()->currentCursor();
    auto geo = cur->geometry();
    if (geo.isEmpty()) {
        return {};
    }

    auto src = cur->source();

    if (auto xsrc = qobject_cast<ShapeCursorSource *>(src)) {
        const auto &img = xsrc->image();
        return {img, cur->hotspot()};
    } else if (auto xsrc = qobject_cast<SurfaceCursorSource *>(src)) {
        auto surface = xsrc->surface();
        auto buf = surface->buffer();
        GraphicsBufferView view(buf);
        if (view.isNull()) {
            return {};
        }
        auto &img = *view.image();
        LogicalOutput *output = workspace()->outputAt(cur->pos());
        if (output) {
            img.setDevicePixelRatio(output->scale());
        } else {
            qCWarning(KWINVR) << "! the cursor is not at any output";
        }

        return {copy ? img.copy() : img, cur->hotspot()};
    }
    return {};
}

void KwinCurrentCursor::setCursorParams(QImage img, QPointF hostspot)
{
    m_hotspot = hostspot;
    m_psize = img.size();
    m_pixelRatio = img.devicePixelRatio();

    setImplicitSize(m_psize.width(), m_psize.height());

    Q_EMIT hotspotChanged();
    Q_EMIT pixelRatioChanged();
    Q_EMIT psizeChanged();
}

QSGNode *KwinCurrentCursor::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    QSGImageNode *node = static_cast<QSGImageNode *>(oldNode);
    if (!node) {
        node = window()->createImageNode();
        node->setFiltering(QSGTexture::Linear);
    }

    auto tex = makeTexture();
    if (tex) {
        setTexture(tex, 0);
        node->setTexture(tex);
        node->setRect(boundingRect());
    }

    return node;
}

QPointF KwinCurrentCursor::hotspot() const
{
    return m_hotspot;
}

qreal KwinCurrentCursor::pixelRatio() const
{
    return m_pixelRatio;
}

QSize KwinCurrentCursor::psize() const
{
    return m_psize;
}
