/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "curvedplanegeometry.h"
#include "geometrytypes.h"
#include <cmath>
#include <cstring>

namespace KWin
{

CurvedPlaneGeometry::CurvedPlaneGeometry(QQuick3DObject *parent)
    : QQuick3DGeometry(parent)
{
    addAttribute(Attribute::PositionSemantic, 0, Attribute::ComponentType::F32Type);
    addAttribute(Attribute::NormalSemantic, 3 * sizeof(float), Attribute::ComponentType::F32Type);
    addAttribute(Attribute::TexCoordSemantic, 6 * sizeof(float), Attribute::ComponentType::F32Type);
    addAttribute(Attribute::IndexSemantic, 0, Attribute::ComponentType::U16Type);
    setStride(sizeof(Vertex));
    setPrimitiveType(PrimitiveType::Triangles);
    rebuildGeometry();
}

void CurvedPlaneGeometry::setWidth(float w)
{
    if (qFuzzyCompare(m_width, w))
        return;
    m_width = w;
    rebuildGeometry();
    Q_EMIT widthChanged();
}

void CurvedPlaneGeometry::setHeight(float h)
{
    if (qFuzzyCompare(m_height, h))
        return;
    m_height = h;
    rebuildGeometry();
    Q_EMIT heightChanged();
}

void CurvedPlaneGeometry::setCurvature(float c)
{
    if (qFuzzyCompare(m_curvature, c))
        return;
    m_curvature = c;
    rebuildGeometry();
    Q_EMIT curvatureChanged();
}

void CurvedPlaneGeometry::setSegments(int s)
{
    s = std::max(1, s);
    if (m_segments == s)
        return;
    m_segments = s;
    rebuildGeometry();
    Q_EMIT segmentsChanged();
}

void CurvedPlaneGeometry::rebuildGeometry()
{
    const int cols = m_segments + 1;
    const int rows = 2; // top and bottom edge
    const int vertexCount = cols * rows;
    const int quadCount = m_segments;
    const int indexCount = quadCount * 6;

    QByteArray vertexData(vertexCount * sizeof(Vertex), Qt::Uninitialized);
    QByteArray indexData(indexCount * sizeof(quint16), Qt::Uninitialized);

    auto *verts = reinterpret_cast<Vertex *>(vertexData.data());
    auto *indices = reinterpret_cast<quint16 *>(indexData.data());

    const float halfW = m_width / 2.0f;
    const float halfH = m_height / 2.0f;
    const float theta = m_curvature; // total arc angle in radians

    for (int col = 0; col < cols; ++col) {
        const float t = static_cast<float>(col) / m_segments; // 0..1
        const float u = t;

        float x, z;
        QVector3D normal;

        if (theta < 0.001f) {
            // Flat plane
            x = -halfW + t * m_width;
            z = 0.0f;
            normal = QVector3D(0.0f, 0.0f, 1.0f);
        } else {
            // Curved: bend along horizontal axis
            const float radius = m_width / theta;
            const float angle = -theta / 2.0f + t * theta;
            x = std::sin(angle) * radius;
            z = -std::cos(angle) * radius + radius;
            normal = QVector3D(std::sin(angle), 0.0f, -std::cos(angle));
            // Flip normal to face outward (toward viewer)
            normal = -normal;
        }

        // Top vertex (row 0)
        verts[col] = {
            QVector3D(x, halfH, z),
            normal,
            QVector2D(u, 1.0f),
        };
        // Bottom vertex (row 1)
        verts[cols + col] = {
            QVector3D(x, -halfH, z),
            normal,
            QVector2D(u, 0.0f),
        };
    }

    // Build triangle indices
    for (int i = 0; i < m_segments; ++i) {
        const quint16 tl = static_cast<quint16>(i);
        const quint16 tr = static_cast<quint16>(i + 1);
        const quint16 bl = static_cast<quint16>(cols + i);
        const quint16 br = static_cast<quint16>(cols + i + 1);

        const int base = i * 6;
        indices[base + 0] = tl;
        indices[base + 1] = bl;
        indices[base + 2] = tr;
        indices[base + 3] = tr;
        indices[base + 4] = bl;
        indices[base + 5] = br;
    }

    setVertexData(vertexData);
    setIndexData(indexData);

    // Compute bounds
    float minX = std::numeric_limits<float>::max();
    float maxX = std::numeric_limits<float>::lowest();
    float maxZ = 0.0f;
    for (int i = 0; i < vertexCount; ++i) {
        minX = std::min(minX, verts[i].position.x());
        maxX = std::max(maxX, verts[i].position.x());
        maxZ = std::max(maxZ, verts[i].position.z());
    }
    setBounds(QVector3D(minX, -halfH, 0.0f), QVector3D(maxX, halfH, maxZ));
    update();
}

} // namespace KWin
