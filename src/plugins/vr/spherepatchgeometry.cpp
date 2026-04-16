/*
    SPDX-FileCopyrightText: 2026 KWin-VR Contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "spherepatchgeometry.h"
#include "geometrytypes.h"
#include <cmath>

namespace KWin
{

SpherePatchGeometry::SpherePatchGeometry(QQuick3DObject *parent)
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

void SpherePatchGeometry::setRadius(float r)
{
    if (qFuzzyCompare(m_radius, r))
        return;
    m_radius = r;
    rebuildGeometry();
    Q_EMIT radiusChanged();
}

void SpherePatchGeometry::setWidthAngle(float a)
{
    if (qFuzzyCompare(m_widthAngle, a))
        return;
    m_widthAngle = a;
    rebuildGeometry();
    Q_EMIT widthAngleChanged();
}

void SpherePatchGeometry::setHeightAngle(float a)
{
    if (qFuzzyCompare(m_heightAngle, a))
        return;
    m_heightAngle = a;
    rebuildGeometry();
    Q_EMIT heightAngleChanged();
}

void SpherePatchGeometry::setColumns(int c)
{
    c = std::max(1, c);
    if (m_columns == c)
        return;
    m_columns = c;
    rebuildGeometry();
    Q_EMIT columnsChanged();
}

void SpherePatchGeometry::setRows(int r)
{
    r = std::max(1, r);
    if (m_rows == r)
        return;
    m_rows = r;
    rebuildGeometry();
    Q_EMIT rowsChanged();
}

void SpherePatchGeometry::rebuildGeometry()
{
    const int cols = m_columns + 1;
    const int rows = m_rows + 1;
    const int vertexCount = cols * rows;
    const int quadCount = m_columns * m_rows;
    const int indexCount = quadCount * 6;

    QByteArray vertexData(vertexCount * sizeof(Vertex), Qt::Uninitialized);
    QByteArray indexData(indexCount * sizeof(quint16), Qt::Uninitialized);

    auto *verts = reinterpret_cast<Vertex *>(vertexData.data());
    auto *indices = reinterpret_cast<quint16 *>(indexData.data());

    float minX = std::numeric_limits<float>::max();
    float maxX = std::numeric_limits<float>::lowest();
    float minY = std::numeric_limits<float>::max();
    float maxY = std::numeric_limits<float>::lowest();
    float minZ = std::numeric_limits<float>::max();
    float maxZ = std::numeric_limits<float>::lowest();

    for (int row = 0; row < rows; ++row) {
        const float v = static_cast<float>(row) / m_rows;
        const float phi = -m_heightAngle * 0.5f + v * m_heightAngle; // latitude, -pi/2..pi/2 range
        const float cosPhi = std::cos(phi);
        const float sinPhi = std::sin(phi);

        for (int col = 0; col < cols; ++col) {
            const float u = static_cast<float>(col) / m_columns;
            const float theta = -m_widthAngle * 0.5f + u * m_widthAngle; // longitude offset around +Z
            const float cosTheta = std::cos(theta);
            const float sinTheta = std::sin(theta);

            QVector3D pos(m_radius * cosPhi * sinTheta,
                          m_radius * sinPhi,
                          m_radius * cosPhi * cosTheta);
            QVector3D normal = pos.normalized();

            const int i = row * cols + col;
            verts[i] = {pos, normal, QVector2D(u, v)};

            minX = std::min(minX, pos.x());
            maxX = std::max(maxX, pos.x());
            minY = std::min(minY, pos.y());
            maxY = std::max(maxY, pos.y());
            minZ = std::min(minZ, pos.z());
            maxZ = std::max(maxZ, pos.z());
        }
    }

    for (int row = 0; row < m_rows; ++row) {
        for (int col = 0; col < m_columns; ++col) {
            const quint16 tl = static_cast<quint16>((row + 1) * cols + col);
            const quint16 tr = static_cast<quint16>((row + 1) * cols + col + 1);
            const quint16 bl = static_cast<quint16>(row * cols + col);
            const quint16 br = static_cast<quint16>(row * cols + col + 1);

            const int base = (row * m_columns + col) * 6;
            indices[base + 0] = tl;
            indices[base + 1] = bl;
            indices[base + 2] = tr;
            indices[base + 3] = tr;
            indices[base + 4] = bl;
            indices[base + 5] = br;
        }
    }

    setVertexData(vertexData);
    setIndexData(indexData);
    setBounds(QVector3D(minX, minY, minZ), QVector3D(maxX, maxY, maxZ));
    update();
}

} // namespace KWin
