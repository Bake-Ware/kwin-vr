/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef KWINCURRENTCURSOR_H
#define KWINCURRENTCURSOR_H

#pragma once

#include "textureprovideritem.h"
#include <QImage>
#include <qsgtextureprovider.h>

namespace KWin
{
class KwinCurrentCursor : public TextureProviderItem
{
    Q_OBJECT
    Q_PROPERTY(QPointF hotspot READ hotspot NOTIFY hotspotChanged FINAL)
    Q_PROPERTY(qreal pixelRatio READ pixelRatio NOTIFY pixelRatioChanged FINAL)
    Q_PROPERTY(QSize psize READ psize NOTIFY psizeChanged FINAL)
    QML_ELEMENT

public:
    KwinCurrentCursor();

    QPointF hotspot() const;
    qreal pixelRatio() const;
    QSize psize() const;

Q_SIGNALS:
    void hotspotChanged();
    void pixelRatioChanged();
    void psizeChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override;

private:
    QSGTexture *makeTexture();

    static std::pair<QImage, QPointF> getCursorImage(bool copy = false);
    void setCursorParams(QImage img, QPointF hostspot);

    QPointF m_hotspot;
    qreal m_pixelRatio;
    QSize m_psize;
};
}
#endif // KWINCURRENTCURSOR_H
