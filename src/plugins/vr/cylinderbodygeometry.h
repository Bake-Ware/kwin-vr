/*
    SPDX-FileCopyrightText: 2026 KWin-VR Contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QQuick3DGeometry>

namespace KWin
{

/**
 * Procedural geometry for a vertical arc slice on a cylinder of given radius
 * and arc angle (in radians). Height is world-units along Y. The arc is
 * centered on +Z and wraps into +X/-X, with the outer (convex) face pointing
 * outward. UVs run 0..1 across the arc (u) and 0..1 top-to-bottom in height
 * (v), matching window texture orientation.
 */
class CylinderBodyGeometry : public QQuick3DGeometry
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(float radius READ radius WRITE setRadius NOTIFY radiusChanged)
    Q_PROPERTY(float arcAngle READ arcAngle WRITE setArcAngle NOTIFY arcAngleChanged)
    Q_PROPERTY(float height READ height WRITE setHeight NOTIFY heightChanged)
    Q_PROPERTY(int segments READ segments WRITE setSegments NOTIFY segmentsChanged)

public:
    explicit CylinderBodyGeometry(QQuick3DObject *parent = nullptr);

    float radius() const
    {
        return m_radius;
    }
    void setRadius(float r);

    float arcAngle() const
    {
        return m_arcAngle;
    }
    void setArcAngle(float a);

    float height() const
    {
        return m_height;
    }
    void setHeight(float h);

    int segments() const
    {
        return m_segments;
    }
    void setSegments(int s);

Q_SIGNALS:
    void radiusChanged();
    void arcAngleChanged();
    void heightChanged();
    void segmentsChanged();

private:
    void rebuildGeometry();

    float m_radius = 30.0f;
    float m_arcAngle = 1.0f;
    float m_height = 40.0f;
    int m_segments = 32;
};

} // namespace KWin
