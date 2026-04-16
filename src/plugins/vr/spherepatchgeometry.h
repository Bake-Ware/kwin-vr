/*
    SPDX-FileCopyrightText: 2026 KWin-VR Contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QQuick3DGeometry>

namespace KWin
{

/**
 * Procedural geometry for a rectangular patch on a sphere. Vertices are placed
 * on the sphere surface so a window texture maps directly onto the curved
 * region. Width/height are the angular extent of the patch in radians
 * (latitude × longitude span), centered on the +Z direction.
 */
class SpherePatchGeometry : public QQuick3DGeometry
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(float radius READ radius WRITE setRadius NOTIFY radiusChanged)
    Q_PROPERTY(float widthAngle READ widthAngle WRITE setWidthAngle NOTIFY widthAngleChanged)
    Q_PROPERTY(float heightAngle READ heightAngle WRITE setHeightAngle NOTIFY heightAngleChanged)
    Q_PROPERTY(int columns READ columns WRITE setColumns NOTIFY columnsChanged)
    Q_PROPERTY(int rows READ rows WRITE setRows NOTIFY rowsChanged)

public:
    explicit SpherePatchGeometry(QQuick3DObject *parent = nullptr);

    float radius() const
    {
        return m_radius;
    }
    void setRadius(float r);

    float widthAngle() const
    {
        return m_widthAngle;
    }
    void setWidthAngle(float a);

    float heightAngle() const
    {
        return m_heightAngle;
    }
    void setHeightAngle(float a);

    int columns() const
    {
        return m_columns;
    }
    void setColumns(int c);

    int rows() const
    {
        return m_rows;
    }
    void setRows(int r);

Q_SIGNALS:
    void radiusChanged();
    void widthAngleChanged();
    void heightAngleChanged();
    void columnsChanged();
    void rowsChanged();

private:
    void rebuildGeometry();

    float m_radius = 30.0f;
    float m_widthAngle = 1.0f;
    float m_heightAngle = 1.0f;
    int m_columns = 24;
    int m_rows = 16;
};

} // namespace KWin
