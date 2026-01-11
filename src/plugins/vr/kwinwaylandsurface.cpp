/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinwaylandsurface.h"
#include "kwingraphicshelpers.h"
#include "kwinvr_logging.h"
#include <QRunnable>
#include <qsgtextureprovider.h>

using namespace KWin;

static QVector4D calculateUVCoords(const QRectF &box, const QSize &bufsz)
{
    double positionU = box.x() / bufsz.width();
    double scaleU = box.width() / bufsz.width();

    double positionV = 1 - ((box.y() + box.height()) / bufsz.height());
    double scaleV = box.height() / bufsz.height();

    return QVector4D(positionU, scaleU, positionV, scaleV);
}

KwinWaylandSurface::KwinWaylandSurface()
{
    setImplicitSize(1, 1);
}

KwinWaylandSurface::~KwinWaylandSurface()
{
}

SurfaceInterface *KwinWaylandSurface::surface() const
{
    return m_surface;
}

void KwinWaylandSurface::setSurface(KWin::SurfaceInterface *newSurface)
{
    if (m_surface == newSurface)
        return;

    if (m_surface) {
        disconnect(m_surface, &SurfaceInterface::committed, this, &KwinWaylandSurface::onSurfaceCommited);
        disconnect(m_surface, &SurfaceInterface::destroyed, this, &KwinWaylandSurface::onSurfaceDestroyed);

        disconnect(m_surface, &SurfaceInterface::bufferSourceBoxChanged, this, &KwinWaylandSurface::onSurfaceBoxChanged);
        disconnect(m_surface, &SurfaceInterface::bufferChanged, this, &KwinWaylandSurface::onSurfaceBoxChanged);

        disconnect(m_surface, &SurfaceInterface::sizeChanged, this, &KwinWaylandSurface::calculateFullOpaque);
        disconnect(m_surface, &SurfaceInterface::opaqueChanged, this, &KwinWaylandSurface::calculateFullOpaque);

        disconnect(m_surface, &SurfaceInterface::sizeChanged, this, &KwinWaylandSurface::calculateNoInput);
        disconnect(m_surface, &SurfaceInterface::inputChanged, this, &KwinWaylandSurface::calculateNoInput);

        disconnect(m_surface, &SurfaceInterface::colorDescriptionChanged, this, &KwinWaylandSurface::yuvMatrixChanged);
    }

    m_surface = newSurface;

    if (m_surface) {
        connect(m_surface, &SurfaceInterface::committed, this, &KwinWaylandSurface::onSurfaceCommited);
        connect(m_surface, &SurfaceInterface::destroyed, this, &KwinWaylandSurface::onSurfaceDestroyed);

        connect(m_surface, &SurfaceInterface::bufferSourceBoxChanged, this, &KwinWaylandSurface::onSurfaceBoxChanged);
        /* For some reason bufferSourceBoxChanged alone is not enough */
        connect(m_surface, &SurfaceInterface::bufferChanged, this, &KwinWaylandSurface::onSurfaceBoxChanged);

        connect(m_surface, &SurfaceInterface::sizeChanged, this, &KwinWaylandSurface::calculateFullOpaque);
        connect(m_surface, &SurfaceInterface::opaqueChanged, this, &KwinWaylandSurface::calculateFullOpaque);

        connect(m_surface, &SurfaceInterface::sizeChanged, this, &KwinWaylandSurface::calculateNoInput);
        connect(m_surface, &SurfaceInterface::inputChanged, this, &KwinWaylandSurface::calculateNoInput);

        connect(m_surface, &SurfaceInterface::colorDescriptionChanged, this, &KwinWaylandSurface::yuvMatrixChanged);

        onSurfaceBoxChanged();
        calculateFullOpaque();
        calculateNoInput();
        onSurfaceCommited();
        Q_EMIT yuvMatrixChanged();
    }

    Q_EMIT surfaceChanged();
}

QSGNode *KwinWaylandSurface::updatePaintNode(QSGNode *, UpdatePaintNodeData *)
{
    auto clear = [&] {
        m_bufferref = nullptr;
        clearTexture();
    };

    if (!m_surface) {
        qCWarning(KWINVR) << "No surface when updatePaintNode is called";
        clear();
        return nullptr;
    }

    auto buf = m_bufferref.buffer();
    if (!buf || buf->size().isEmpty()) {
        clear();
        return nullptr;
    }

    auto textures = loadGraphicsBufferToQSGTextures(buf, window());
    if (!textures.planeCount) {
        clear();
        return nullptr;
    }

    auto &currentPair = textures.planeTextures[0];
    auto &glTexture = currentPair.glTexture;
    auto &qsgTexture = currentPair.qtTexture;

    qsgTexture->setFiltering(QSGTexture::Linear);
    qsgTexture->setHorizontalWrapMode(QSGTexture::ClampToEdge);
    qsgTexture->setVerticalWrapMode(QSGTexture::ClampToEdge);

    setTexture(qsgTexture, glTexture);

    auto uv = uvTextureItem();
    if (textures.planeCount == 2) {
        const auto &uvTexture = textures.planeTextures[1];
        auto &qsgTexture = uvTexture.qtTexture;
        qsgTexture->setFiltering(QSGTexture::Linear);
        qsgTexture->setHorizontalWrapMode(QSGTexture::ClampToEdge);
        qsgTexture->setVerticalWrapMode(QSGTexture::ClampToEdge);

        if (!uv) {
            uv = new TextureProviderItem(this);
            uv->setTexture(uvTexture.qtTexture, uvTexture.glTexture);
            uv->moveToThread(thread());
            setUvTextureItem(uv);
        } else {
            uv->setTexture(uvTexture.qtTexture, uvTexture.glTexture);
        }
    } else {
        if (uv) {
            uv->clearTexture();
            setUvTextureItem(nullptr);
        }
    }

    return nullptr;
}

void KwinWaylandSurface::onSurfaceCommited()
{
    m_bufferref = m_surface->buffer();
    qCDebug(KWINVR) << "On commited" << m_surface << "sur size" << m_surface->size() << "buf" << m_surface->buffer() << "bufsize" << (m_surface->buffer() ? m_surface->buffer()->size() : QSize());
    update();
}

void KwinWaylandSurface::calculateFullOpaque()
{
    if (!m_surface)
        return;

    // TODO: Need a beter way to know if this surface is fully opaque
    auto opq = m_surface->opaque();

    // Kwin 6.5 compat
    using rect = decltype(opq.boundingRect());
    rect sizeRect(QPoint(0, 0), m_surface->size().toSize());
    bool res = !opq.isEmpty() && opq.intersected(sizeRect) == sizeRect;

    setFullyOpaque(res);
}

void KwinWaylandSurface::calculateNoInput()
{
    setNoInput(m_surface && m_surface->input().isEmpty());
}

void KwinWaylandSurface::releaseResources()
{
    m_bufferref = nullptr;
    TextureProviderItem::releaseResources();
}

void KwinWaylandSurface::onSurfaceDestroyed()
{
    m_surface = nullptr;
    m_bufferref = nullptr;
    Q_EMIT surfaceChanged();
}

void KwinWaylandSurface::onSurfaceBoxChanged()
{
    if (!m_surface) {
        qCWarning(KWINVR) << "! No surface when calculating uv coordinates";
        return;
    }

    auto buf = m_surface->buffer();
    if (!buf) {
        qCWarning(KWINVR) << "! No buffer when calculating uv coordinates";
        return;
    }

    auto coords = calculateUVCoords(m_surface->bufferSourceBox(), buf->size());
    if (coords == m_uvCoords)
        return;

    m_uvCoords = coords;
    Q_EMIT uvCoordsChanged();
}

QVector4D KwinWaylandSurface::uvCoords() const
{
    return m_uvCoords;
}

bool KwinWaylandSurface::fullyOpaque() const
{
    return m_fullyOpaque;
}

void KwinWaylandSurface::setFullyOpaque(bool newFullyOpaque)
{
    if (m_fullyOpaque == newFullyOpaque)
        return;
    m_fullyOpaque = newFullyOpaque;
    Q_EMIT fullyOpaqueChanged();
}

bool KwinWaylandSurface::noInput() const
{
    return m_noInput;
}

void KwinWaylandSurface::setNoInput(bool newNoInput)
{
    if (m_noInput == newNoInput)
        return;
    qCWarning(KWINVR) << "Setting no input to" << newNoInput << m_surface;
    m_noInput = newNoInput;
    Q_EMIT noInputChanged();
}

TextureProviderItem *KwinWaylandSurface::uvTextureItem() const
{
    return m_uvTextureItem;
}

void KwinWaylandSurface::setUvTextureItem(KWin::TextureProviderItem *newUvTextureItem)
{
    if (m_uvTextureItem == newUvTextureItem)
        return;

    if (m_uvTextureItem)
        m_uvTextureItem->deleteLater();

    m_uvTextureItem = newUvTextureItem;
    Q_EMIT uvTextureItemChanged();
}

QMatrix4x4 KwinWaylandSurface::yuvMatrix() const
{
    if (!m_surface) {
        return {};
    }

    return m_surface->colorDescription()->yuvMatrix();
}
