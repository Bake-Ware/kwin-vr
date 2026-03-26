/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "internalwindow.h"
#include "renderbufferholder.h"
#include "textureprovideritem.h"

#include <QQuickItem>

#include <memory>

namespace KWin
{

class KwinInternalWindow : public TextureProviderItem
{
    Q_OBJECT
    Q_PROPERTY(KWin::InternalWindow *client READ client WRITE setClient NOTIFY clientChanged FINAL)
    Q_PROPERTY(bool flipU READ flipU NOTIFY flipUChanged FINAL)
    Q_PROPERTY(bool flipV READ flipV NOTIFY flipVChanged FINAL)
    QML_ELEMENT
public:
    KwinInternalWindow();
    ~KwinInternalWindow() override;

    InternalWindow *client() const;
    void setClient(InternalWindow *newClient);

    QSGNode *updatePaintNode(QSGNode *oldNode, QQuickItem::UpdatePaintNodeData *) override;

    bool flipU() const;
    bool flipV() const;

Q_SIGNALS:
    void clientChanged();
    void flipUChanged();
    void flipVChanged();

protected:
    void invalidateSceneGraph() override;
    void releaseResources() override;
    void setFlipU(bool newFlipU);
    void setFlipV(bool newFlipV);

private:
    void onPresented(const InternalWindowFrame &frame);
    void onClientGeometryChanged();
    void onWindowDestroyed();
    void deferRenderHolderRelease();

    InternalWindow *m_client = nullptr;

    GraphicsBufferRef m_bufferRef;
    std::unique_ptr<RenderBufferHolder> m_renderHolder;
    OutputTransform m_bufferTransform = OutputTransform::Kind::Normal;

    bool m_flipU = false;
    bool m_flipV = false;
};

} // namespace KWin
