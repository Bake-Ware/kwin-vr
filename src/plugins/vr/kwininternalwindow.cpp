/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwininternalwindow.h"
#include "kwingraphicshelpers.h"

#include <QRunnable>

namespace KWin
{

KwinInternalWindow::KwinInternalWindow()
{
}

KwinInternalWindow::~KwinInternalWindow()
{
    deferRenderHolderRelease();
    releaseResources();
}

InternalWindow *KwinInternalWindow::client() const
{
    return m_client;
}

void KwinInternalWindow::setClient(InternalWindow *newClient)
{
    if (m_client == newClient) {
        return;
    }

    if (m_client) {
        disconnect(m_client, &InternalWindow::presented, this, &KwinInternalWindow::onPresented);
        disconnect(m_client, &InternalWindow::clientGeometryChanged, this, &KwinInternalWindow::onClientGeometryChanged);
        disconnect(m_client, &InternalWindow::destroyed, this, &KwinInternalWindow::onWindowDestroyed);
    }

    m_client = newClient;

    if (newClient) {
        connect(newClient, &InternalWindow::presented, this, &KwinInternalWindow::onPresented);
        connect(newClient, &InternalWindow::clientGeometryChanged, this, &KwinInternalWindow::onClientGeometryChanged);
        connect(newClient, &InternalWindow::destroyed, this, &KwinInternalWindow::onWindowDestroyed);
    }

    onClientGeometryChanged();
    onPresented({});

    Q_EMIT clientChanged();
}

QSGNode *KwinInternalWindow::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    QSGImageNode *node = static_cast<QSGImageNode *>(oldNode);
    if (!node) {
        node = window()->createImageNode();
        node->setFiltering(QSGTexture::Linear);
        node->setTextureCoordinatesTransform(QSGImageNode::NoTransform);
    }

    auto clear = [&] {
        m_renderHolder.reset();
        m_bufferRef = nullptr;
        delete node;
        clearTexture();
    };

    auto buf = m_bufferRef.buffer();
    if (!buf) {
        clear();
        return nullptr;
    }

    if (buf->size().isEmpty()) {
        clear();
        return nullptr;
    }

    if (!m_renderHolder) {
        m_renderHolder = std::make_unique<RenderBufferHolder>();
    }
    m_renderHolder->reset(buf);

    auto textures = loadGraphicsBufferToQSGTextures(buf, window(), m_renderHolder->view());
    if (!textures.planeCount) {
        m_bufferRef = nullptr;
        delete node;
        clearTexture();
        return nullptr;
    }

    // Use the first plane
    auto currentPair = textures.planeTextures[0];

    // TODO: YUV
    textures.planeTextures[0] = {};
    textures.release();

    auto glTexture = currentPair.glTexture;
    auto qsgTexture = currentPair.qtTexture;

    qsgTexture->setFiltering(QSGTexture::Linear);
    qsgTexture->setHorizontalWrapMode(QSGTexture::ClampToEdge);
    qsgTexture->setVerticalWrapMode(QSGTexture::ClampToEdge);

    setTexture(qsgTexture, glTexture);

    // Well, this is kinda limited
    node->setTextureCoordinatesTransform(
        (m_bufferTransform == OutputTransform::FlipX ? QSGImageNode::MirrorHorizontally : QSGImageNode::NoTransform) | (m_bufferTransform == OutputTransform::FlipY ? QSGImageNode::MirrorVertically : QSGImageNode::NoTransform));

    node->setTexture(qsgTexture);
    node->setRect(boundingRect());

    return node;
}

void KwinInternalWindow::invalidateSceneGraph()
{
    m_renderHolder.reset();
    TextureProviderItem::invalidateSceneGraph();
}

void KwinInternalWindow::releaseResources()
{
    deferRenderHolderRelease();
    m_bufferRef = nullptr;
    TextureProviderItem::releaseResources();
}

void KwinInternalWindow::deferRenderHolderRelease()
{
    if (!m_renderHolder) {
        return;
    }
    auto *win = window();
    if (win) {
        auto *holder = m_renderHolder.release();
        win->scheduleRenderJob(
            QRunnable::create([holder]() {
            delete holder;
        }),
            QQuickWindow::BeforeSynchronizingStage);
    }
}

void KwinInternalWindow::onPresented(const InternalWindowFrame &)
{
    if (!m_client) {
        m_bufferRef = nullptr;
        return;
    }

    auto buf = m_client->graphicsBuffer();
    if (!buf) {
        m_bufferRef = nullptr;
        return;
    }

    m_bufferRef = buf;
    m_bufferTransform = m_client->bufferTransform();

    setFlipU(m_bufferTransform == OutputTransform::FlipX);
    setFlipV(m_bufferTransform == OutputTransform::FlipY);

    update();
}

void KwinInternalWindow::onClientGeometryChanged()
{
    if (!m_client) {
        setImplicitSize(1, 1);
        return;
    }

    auto geo = m_client->clientGeometry();
    setImplicitSize(geo.width(), geo.height());
}

void KwinInternalWindow::onWindowDestroyed()
{
    m_client = nullptr;
    m_bufferRef = nullptr;
    setImplicitSize(1, 1);
    update();
    Q_EMIT clientChanged();
}

bool KwinInternalWindow::flipU() const
{
    return m_flipU;
}

void KwinInternalWindow::setFlipU(bool newFlipU)
{
    if (m_flipU == newFlipU) {
        return;
    }
    m_flipU = newFlipU;
    Q_EMIT flipUChanged();
}

bool KwinInternalWindow::flipV() const
{
    return m_flipV;
}

void KwinInternalWindow::setFlipV(bool newFlipV)
{
    if (m_flipV == newFlipV) {
        return;
    }
    m_flipV = newFlipV;
    Q_EMIT flipVChanged();
}

} // namespace KWin
