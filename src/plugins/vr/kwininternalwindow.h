/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef KWININTERNALWINDOW_H
#define KWININTERNALWINDOW_H

#include "internalwindow.h"
#include "textureprovideritem.h"
#include <QQuickItem>

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
    ~KwinInternalWindow();

    KWin::InternalWindow *client() const;
    void setClient(KWin::InternalWindow *newClient);

    QSGNode *updatePaintNode(QSGNode *oldNode, QQuickItem::UpdatePaintNodeData *) override;

    bool flipU() const;
    bool flipV() const;

Q_SIGNALS:
    void clientChanged();
    void flipUChanged();
    void flipVChanged();

private Q_SLOTS:
    void onPresented(const KWin::InternalWindowFrame &frame);
    void onClientGeometryChanged();
    void onWindowDestoyed();

protected:
    void releaseResources() override;
    void setFlipU(bool newFlipU);
    void setFlipV(bool newFlipV);

private:
    KWin::InternalWindow *m_client = nullptr;

    GraphicsBufferRef m_bufferref;
    OutputTransform m_bufferTransform = OutputTransform::Kind::Normal;

    bool m_flipU;
    bool m_flipV;
};
}

#endif // KWININTERNALWINDOW_H
