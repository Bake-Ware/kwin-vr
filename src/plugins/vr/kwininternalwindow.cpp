/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwininternalwindow.h"
#include "kwingraphicshelpers.h"
#include <QRunnable>
#include <qsgtextureprovider.h>

using namespace KWin;

KwinInternalWindow::KwinInternalWindow()
{
}

KwinInternalWindow::~KwinInternalWindow()
{
    releaseResources();
}

InternalWindow *KwinInternalWindow::client() const
{
    return m_client;
}

void KwinInternalWindow::setClient(KWin::InternalWindow *newClient)
{
    if (m_client == newClient)
        return;

    if (m_client) {
        disconnect(m_client, &InternalWindow::presented, this, &KwinInternalWindow::onPresented);
        disconnect(m_client, &InternalWindow::clientGeometryChanged, this, &KwinInternalWindow::onClientGeometryChanged);
    }

    m_client = newClient;

    if (newClient) {
        connect(newClient, &InternalWindow::presented, this, &KwinInternalWindow::onPresented);
        connect(newClient, &InternalWindow::clientGeometryChanged, this, &KwinInternalWindow::onClientGeometryChanged);
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

    auto buf = m_bufferref.buffer();
    if (!buf) {
        delete node;
        clearTexture();
        return nullptr;
    }

    if (buf->size().isEmpty()) {
        m_bufferref = nullptr;
        delete node;
        clearTexture();
        return nullptr;
    }

    auto textures = loadGraphicsBufferToQSGTextures(buf, window());
    if (!textures.planeCount) {
        m_bufferref = nullptr;
        delete node;
        clearTexture();
        return nullptr;
    }

    // Use the last plane justs for fun
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

    /* Well, this is kinda limited */
    node->setTextureCoordinatesTransform(
        (m_bufferTransform == OutputTransform::FlipX ? QSGImageNode::MirrorHorizontally : QSGImageNode::NoTransform) | (m_bufferTransform == OutputTransform::FlipY ? QSGImageNode::MirrorVertically : QSGImageNode::NoTransform));

    node->setTexture(qsgTexture);
    // node->setSourceRect({QPointF(0,0), buf->size()});
    node->setRect(boundingRect());

    return node;
}

void KwinInternalWindow::releaseResources()
{
    m_bufferref = nullptr;
    TextureProviderItem::releaseResources();
}

void KwinInternalWindow::onPresented(const KWin::InternalWindowFrame &frame)
{
    Q_UNUSED(frame);

    if (!m_client) {
        m_bufferref = nullptr;
        return;
    }

    auto buf = m_client->graphicsBuffer();
    if (!buf) {
        m_bufferref = nullptr;
        return;
    }

    m_bufferref = buf;
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

void KwinInternalWindow::onWindowDestoyed()
{
    m_bufferref = nullptr;
    setImplicitSize(1, 1);
}

bool KwinInternalWindow::flipU() const
{
    return m_flipU;
}

void KwinInternalWindow::setFlipU(bool newFlipU)
{
    if (m_flipU == newFlipU)
        return;
    m_flipU = newFlipU;
    Q_EMIT flipUChanged();
}

bool KwinInternalWindow::flipV() const
{
    return m_flipV;
}

void KwinInternalWindow::setFlipV(bool newFlipV)
{
    if (m_flipV == newFlipV)
        return;
    m_flipV = newFlipV;
    Q_EMIT flipVChanged();
}
