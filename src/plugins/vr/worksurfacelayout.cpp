/*
    SPDX-FileCopyrightText: 2026 KWin-VR Contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "worksurfacelayout.h"
#include "worksurfacemodel.h" // for WorkSurfaceLayout::Mode enum

#include <QtMath>

namespace KWin
{

WorkSurfaceLayoutEngine::WorkSurfaceLayoutEngine(QObject *parent)
    : QObject(parent)
{
}

QVariantList WorkSurfaceLayoutEngine::computeLayout(int layoutMode, const QSizeF &faceSize,
                                                    const QVariantList &windowSizesVar, int activeIndex)
{
    QList<QSizeF> windowSizes;
    windowSizes.reserve(windowSizesVar.size());
    for (const auto &v : windowSizesVar) {
        windowSizes.append(v.toSizeF());
    }

    QList<LayoutSlot> slots;
    switch (layoutMode) {
    case WorkSurfaceLayout::Masonry:
        slots = layoutMasonry(faceSize, windowSizes);
        break;
    case WorkSurfaceLayout::Grid:
        slots = layoutGrid(faceSize, windowSizes);
        break;
    case WorkSurfaceLayout::Stack:
        slots = layoutStack(faceSize, windowSizes, activeIndex);
        break;
    case WorkSurfaceLayout::Freeform:
        slots = layoutFreeform(faceSize, windowSizes);
        break;
    case WorkSurfaceLayout::Cover:
        slots = layoutCover(faceSize, windowSizes, activeIndex);
        break;
    default:
        slots = layoutMasonry(faceSize, windowSizes);
        break;
    }

    QVariantList result;
    result.reserve(slots.size());
    for (const auto &slot : slots) {
        result.append(QVariant::fromValue(slot));
    }
    return result;
}

// -- Masonry layout ---------------------------------------------------------
// Pack windows into columns, placing each window into the shortest column.
// Windows are scaled to fit the column width while preserving aspect ratio.

QList<LayoutSlot> WorkSurfaceLayoutEngine::layoutMasonry(const QSizeF &faceSize, const QList<QSizeF> &windowSizes)
{
    const int n = windowSizes.size();
    if (n == 0) {
        return {};
    }

    // Choose column count based on window count
    const int cols = qMax(1, qMin(n, static_cast<int>(qCeil(qSqrt(n)))));
    const qreal padding = faceSize.width() * 0.02;
    const qreal colWidth = (faceSize.width() - padding * (cols + 1)) / cols;

    // Track the current height of each column
    QList<qreal> colHeights(cols, padding);

    QList<LayoutSlot> slots;
    slots.reserve(n);

    for (int i = 0; i < n; ++i) {
        // Find the shortest column
        int shortestCol = 0;
        for (int c = 1; c < cols; ++c) {
            if (colHeights[c] < colHeights[shortestCol]) {
                shortestCol = c;
            }
        }

        const QSizeF &winSize = windowSizes[i];
        const qreal aspect = winSize.height() / qMax(winSize.width(), 0.001);
        const qreal scaledHeight = colWidth * aspect;

        const qreal x = padding + shortestCol * (colWidth + padding);
        const qreal y = colHeights[shortestCol];

        LayoutSlot slot;
        slot.rect = QRectF(x, y, colWidth, scaledHeight);
        slot.zOrder = i;
        slot.scale = colWidth / qMax(winSize.width(), 0.001);
        slots.append(slot);

        colHeights[shortestCol] += scaledHeight + padding;
    }

    return slots;
}

// -- Grid layout ------------------------------------------------------------
// Equal-cell grid. Rows and cols auto-calculated. Windows scale to fit cells.

QList<LayoutSlot> WorkSurfaceLayoutEngine::layoutGrid(const QSizeF &faceSize, const QList<QSizeF> &windowSizes)
{
    const int n = windowSizes.size();
    if (n == 0) {
        return {};
    }

    const int cols = qMax(1, static_cast<int>(qCeil(qSqrt(n))));
    const int rows = qMax(1, static_cast<int>(qCeil(static_cast<qreal>(n) / cols)));
    const qreal padding = faceSize.width() * 0.02;
    const qreal cellW = (faceSize.width() - padding * (cols + 1)) / cols;
    const qreal cellH = (faceSize.height() - padding * (rows + 1)) / rows;

    QList<LayoutSlot> slots;
    slots.reserve(n);

    for (int i = 0; i < n; ++i) {
        const int row = i / cols;
        const int col = i % cols;
        const qreal x = padding + col * (cellW + padding);
        const qreal y = padding + row * (cellH + padding);

        const QSizeF &winSize = windowSizes[i];
        // Scale window to fit within cell preserving aspect ratio
        const qreal scaleX = cellW / qMax(winSize.width(), 0.001);
        const qreal scaleY = cellH / qMax(winSize.height(), 0.001);
        const qreal s = qMin(scaleX, scaleY);

        const qreal w = winSize.width() * s;
        const qreal h = winSize.height() * s;
        // Center within cell
        const qreal cx = x + (cellW - w) / 2;
        const qreal cy = y + (cellH - h) / 2;

        LayoutSlot slot;
        slot.rect = QRectF(cx, cy, w, h);
        slot.zOrder = i;
        slot.scale = s;
        slots.append(slot);
    }

    return slots;
}

// -- Stack layout -----------------------------------------------------------
// All windows stacked at center, only activeIndex is fully visible.

QList<LayoutSlot> WorkSurfaceLayoutEngine::layoutStack(const QSizeF &faceSize, const QList<QSizeF> &windowSizes, int activeIndex)
{
    const int n = windowSizes.size();
    if (n == 0) {
        return {};
    }

    activeIndex = qBound(0, activeIndex, n - 1);

    QList<LayoutSlot> slots;
    slots.reserve(n);

    for (int i = 0; i < n; ++i) {
        const QSizeF &winSize = windowSizes[i];
        // Scale to fit 90% of the face
        const qreal scaleX = (faceSize.width() * 0.9) / qMax(winSize.width(), 0.001);
        const qreal scaleY = (faceSize.height() * 0.9) / qMax(winSize.height(), 0.001);
        const qreal s = qMin(scaleX, scaleY);

        const qreal w = winSize.width() * s;
        const qreal h = winSize.height() * s;
        const qreal x = (faceSize.width() - w) / 2;
        const qreal y = (faceSize.height() - h) / 2;

        LayoutSlot slot;
        slot.rect = QRectF(x, y, w, h);
        // Active window on top
        slot.zOrder = (i == activeIndex) ? n : i;
        slot.scale = s;
        slots.append(slot);
    }

    return slots;
}

// -- Freeform layout --------------------------------------------------------
// Windows keep their current positions. Just provide initial centered placement.

QList<LayoutSlot> WorkSurfaceLayoutEngine::layoutFreeform(const QSizeF &faceSize, const QList<QSizeF> &windowSizes)
{
    const int n = windowSizes.size();
    if (n == 0) {
        return {};
    }

    QList<LayoutSlot> slots;
    slots.reserve(n);

    for (int i = 0; i < n; ++i) {
        const QSizeF &winSize = windowSizes[i];
        // Place at center, no scaling
        const qreal x = (faceSize.width() - winSize.width()) / 2;
        const qreal y = (faceSize.height() - winSize.height()) / 2;

        LayoutSlot slot;
        slot.rect = QRectF(x, y, winSize.width(), winSize.height());
        slot.zOrder = i;
        slot.scale = 1.0;
        slots.append(slot);
    }

    return slots;
}

// -- Cover layout -----------------------------------------------------------
// Single window fills the face. activeIndex selects which one.

QList<LayoutSlot> WorkSurfaceLayoutEngine::layoutCover(const QSizeF &faceSize, const QList<QSizeF> &windowSizes, int activeIndex)
{
    const int n = windowSizes.size();
    if (n == 0) {
        return {};
    }

    activeIndex = qBound(0, activeIndex, n - 1);

    QList<LayoutSlot> slots;
    slots.reserve(n);

    for (int i = 0; i < n; ++i) {
        const QSizeF &winSize = windowSizes[i];

        if (i == activeIndex) {
            // Fill the face, preserving aspect ratio
            const qreal scaleX = faceSize.width() / qMax(winSize.width(), 0.001);
            const qreal scaleY = faceSize.height() / qMax(winSize.height(), 0.001);
            const qreal s = qMin(scaleX, scaleY);

            const qreal w = winSize.width() * s;
            const qreal h = winSize.height() * s;
            const qreal x = (faceSize.width() - w) / 2;
            const qreal y = (faceSize.height() - h) / 2;

            LayoutSlot slot;
            slot.rect = QRectF(x, y, w, h);
            slot.zOrder = n;
            slot.scale = s;
            slots.append(slot);
        } else {
            // Hidden behind the active window
            LayoutSlot slot;
            slot.rect = QRectF(0, 0, 0, 0);
            slot.zOrder = i;
            slot.scale = 0;
            slots.append(slot);
        }
    }

    return slots;
}

} // namespace KWin
