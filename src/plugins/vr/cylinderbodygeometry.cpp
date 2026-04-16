/*
    SPDX-FileCopyrightText: 2026 KWin-VR Contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "cylinderbodygeometry.h"
#include "geometrytypes.h"
#include <cmath>

namespace KWin
{

CylinderBodyGeometry::CylinderBodyGeometry(QQuick3DObject *parent)
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

void CylinderBodyGeometry::setRadius(float r)
{
    if (qFuzzyCompare(m_radius, r))
        return;
    m_radius = r;
    rebuildGeometry();
    Q_EMIT radiusChanged();
}

void CylinderBodyGeometry::setArcAngle(float a)
{
    if (qFuzzyCompare(m_arcAngle, a))
        return;
    m_arcAngle = a;
    rebuildGeometry();
    Q_EMIT arcAngleChanged();
}

void CylinderBodyGeometry::setHeight(float h)
{
    if (qFuzzyCompare(m_height, h))
        return;
    m_height = h;
    rebuildGeometry();
    Q_EMIT heightChanged();
}

void CylinderBodyGeometry::setSegments(int s)
{
    s = std::max(1, s);
    if (m_segments == s)
        return;
    m_segments = s;
    rebuildGeometry();
    Q_EMIT segmentsChanged();
}

void CylinderBodyGeometry::rebuildGeometry()
{
    const int cols = m_segments + 1;
    const int rows = 2;
    const int vertexCount = cols * rows;
    const int quadCount = m_segments;
    const int indexCount = quadCount * 6;

    QByteArray vertexData(vertexCount * sizeof(Vertex), Qt::Uninitialized);
    QByteArray indexData(indexCount * sizeof(quint16), Qt::Uninitialized);

    auto *verts = reinterpret_cast<Vertex *>(vertexData.data());
    auto *indices = reinterpret_cast<quint16 *>(indexData.data());

    const float halfH = m_height * 0.5f;
    float minX = std::numeric_limits<float>::max();
    float maxX = std::numeric_limits<float>::lowest();
    float maxZ = std::numeric_limits<float>::lowest();
    float minZ = std::numeric_limits<float>::max();

    for (int col = 0; col < cols; ++col) {
        const float u = static_cast<float>(col) / m_segments; // 0..1
        const float angle = -m_arcAngle * 0.5f + u * m_arcAngle;

        const float x = std::sin(angle) * m_radius;
        const float z = std::cos(angle) * m_radius;

        // Outward normal (radial from cylinder axis, in xz plane)
        const QVector3D normal(std::sin(angle), 0.0f, std::cos(angle));

        // Top row (v=1)
        verts[col] = {
            QVector3D(x, halfH, z),
            normal,
            QVector2D(u, 1.0f),
        };
        // Bottom row (v=0)
        verts[cols + col] = {
            QVector3D(x, -halfH, z),
            normal,
            QVector2D(u, 0.0f),
        };

        minX = std::min(minX, x);
        maxX = std::max(maxX, x);
        minZ = std::min(minZ, z);
        maxZ = std::max(maxZ, z);
    }

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
    setBounds(QVector3D(minX, -halfH, minZ), QVector3D(maxX, halfH, maxZ));
    update();
}

} // namespace KWin
