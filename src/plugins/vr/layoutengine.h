/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QVariantList>
#include <QVector3D>
#include <QtQml/qqmlregistration.h>

namespace KWin
{

/**
 * QML-facing facade over the per-item layout-mode helpers. Exposed as
 * a singleton so QML callers (CurvedPlane) can compute a single
 * slot's pose without needing a full Qt scene-graph layout pass.
 *
 * Batch layout (whole-container-at-once via VolumetricStacker) routes
 * through ILayoutMode classes; this engine is the per-item path.
 */
class LayoutEngine : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    explicit LayoutEngine(QObject *parent = nullptr);

    Q_INVOKABLE QVector3D cascadePosition(int idx, qreal stepX, qreal stepY, qreal stepZ) const;
    Q_INVOKABLE QVector3D snapRowPosition(int idx, const QVariantList &widths, qreal gap) const;
    Q_INVOKABLE qreal freeStackZ(int idx, qreal step) const;
};

} // namespace KWin
