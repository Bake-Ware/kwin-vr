/*
    SPDX-FileCopyrightText: 2026 KWin-VR Contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QList>
#include <QObject>
#include <QRectF>
#include <QSizeF>
#include <QtQmlIntegration>

namespace KWin
{

/**
 * A computed position and scale for a single window within a face layout.
 */
struct LayoutSlot
{
    Q_GADGET
    Q_PROPERTY(QRectF rect MEMBER rect)
    Q_PROPERTY(int zOrder MEMBER zOrder)
    Q_PROPERTY(qreal scale MEMBER scale)
    QML_VALUE_TYPE(layoutSlot)
    QML_STRUCTURED_VALUE
public:
    QRectF rect;
    int zOrder = 0;
    qreal scale = 1.0;
};

/**
 * Computes window positions within a rectangular face region.
 *
 * Given a layout mode, the face dimensions, and a list of window sizes,
 * produces a LayoutSlot for each window describing where it should be
 * placed on the face.
 */
class WorkSurfaceLayoutEngine : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit WorkSurfaceLayoutEngine(QObject *parent = nullptr);

    /**
     * Compute layout slots for the given windows on a face.
     *
     * @param layoutMode  One of WorkSurfaceLayout::Mode values
     * @param faceSize    The face dimensions in world units
     * @param windowSizes List of window sizes in world units
     * @param activeIndex For Stack/Cover modes, which window is on top
     * @return List of LayoutSlot, one per window
     */
    Q_INVOKABLE QVariantList computeLayout(int layoutMode, const QSizeF &faceSize,
                                           const QVariantList &windowSizes, int activeIndex = 0);

private:
    QList<LayoutSlot> layoutMasonry(const QSizeF &faceSize, const QList<QSizeF> &windowSizes);
    QList<LayoutSlot> layoutGrid(const QSizeF &faceSize, const QList<QSizeF> &windowSizes);
    QList<LayoutSlot> layoutStack(const QSizeF &faceSize, const QList<QSizeF> &windowSizes, int activeIndex);
    QList<LayoutSlot> layoutFreeform(const QSizeF &faceSize, const QList<QSizeF> &windowSizes);
    QList<LayoutSlot> layoutCover(const QSizeF &faceSize, const QList<QSizeF> &windowSizes, int activeIndex);
};

} // namespace KWin
