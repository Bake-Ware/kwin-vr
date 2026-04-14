/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QQuick3DGeometry>

namespace KWin
{

/**
 * Procedural geometry for a rectangular plane that can be curved
 * horizontally (like a curved monitor). Curvature is the total arc
 * angle in radians (0 = flat, pi = half-cylinder).
 */
class CurvedPlaneGeometry : public QQuick3DGeometry
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(float width READ width WRITE setWidth NOTIFY widthChanged)
    Q_PROPERTY(float height READ height WRITE setHeight NOTIFY heightChanged)
    Q_PROPERTY(float curvature READ curvature WRITE setCurvature NOTIFY curvatureChanged)
    Q_PROPERTY(int segments READ segments WRITE setSegments NOTIFY segmentsChanged)

public:
    explicit CurvedPlaneGeometry(QQuick3DObject *parent = nullptr);

    float width() const
    {
        return m_width;
    }
    void setWidth(float w);

    float height() const
    {
        return m_height;
    }
    void setHeight(float h);

    float curvature() const
    {
        return m_curvature;
    }
    void setCurvature(float c);

    int segments() const
    {
        return m_segments;
    }
    void setSegments(int s);

Q_SIGNALS:
    void widthChanged();
    void heightChanged();
    void curvatureChanged();
    void segmentsChanged();

private:
    void rebuildGeometry();

    float m_width = 100.0f;
    float m_height = 100.0f;
    float m_curvature = 0.0f;
    int m_segments = 32;
};

} // namespace KWin
