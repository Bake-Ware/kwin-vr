/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef KWINWAYLANDSURFACE_H
#define KWINWAYLANDSURFACE_H

#include "core/graphicsbuffer.h"
#include "kwinasyncreadback.h"
#include "textureprovideritem.h"
#include "wayland/subcompositor.h"
#include "wayland/surface.h"
#include "window.h"
#include <QAbstractListModel>
#include <QQuickItem>

namespace KWin
{
class KwinWaylandSurface : public TextureProviderItem
{
    Q_OBJECT
    Q_PROPERTY(KWin::SurfaceInterface *surface READ surface WRITE setSurface NOTIFY surfaceChanged FINAL)
    Q_PROPERTY(QVector4D uvCoords READ uvCoords NOTIFY uvCoordsChanged FINAL)
    Q_PROPERTY(bool fullyOpaque READ fullyOpaque NOTIFY fullyOpaqueChanged FINAL)
    Q_PROPERTY(bool noInput READ noInput NOTIFY noInputChanged FINAL)

    Q_PROPERTY(KWin::TextureProviderItem *uvTexture READ uvTextureItem WRITE setUvTextureItem NOTIFY uvTextureItemChanged FINAL)
    Q_PROPERTY(QMatrix4x4 yuvMatrix READ yuvMatrix NOTIFY yuvMatrixChanged FINAL)
    QML_ELEMENT
public:
    KwinWaylandSurface();
    ~KwinWaylandSurface();

    KWin::SurfaceInterface *surface() const;
    void setSurface(KWin::SurfaceInterface *newSurface);

    QSGNode *updatePaintNode(QSGNode *oldNode, QQuickItem::UpdatePaintNodeData *) override;

    QVector4D uvCoords() const;
    bool fullyOpaque() const;
    bool noInput() const;
    KWin::TextureProviderItem *uvTextureItem() const;
    void setUvTextureItem(KWin::TextureProviderItem *newUvTexture);
    QMatrix4x4 yuvMatrix() const;

Q_SIGNALS:
    void surfaceChanged();
    void uvCoordsChanged();
    void fullyOpaqueChanged();
    void noInputChanged();

    void uvTextureItemChanged();
    void yuvMatrixChanged();

private Q_SLOTS:
    void onSurfaceCommited();
    void onSurfaceDestroyed();
    void onSurfaceBoxChanged();

protected:
    void releaseResources() override;

private:
    void setFullyOpaque(bool newFullyOpaque);
    void setNoInput(bool newNoInput);
    void calculateFullOpaque();
    void calculateNoInput();

    KWin::SurfaceInterface *m_surface = nullptr;
    GraphicsBufferRef m_bufferref;

    mutable QSGTextureProvider *m_textprov = nullptr;
    QVector4D m_uvCoords;
    bool m_fullyOpaque = false;
    bool m_noInput = false;

    KWin::TextureProviderItem *m_uvTextureItem = nullptr;

    // Render-thread-only: async PBO readback state for Vulkan RHI path
    AsyncReadbackState m_asyncReadback;
};
}

#endif // KWINWAYLANDSURFACE_H
