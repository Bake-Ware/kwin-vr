/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "curvedwindowgeometry.h"
#include "geometrytypes.h"
#include <cmath>
#include <cstring>

using namespace KWin;

static constexpr int Segments = 32;
static constexpr int Cols = Segments + 1; // 33
static constexpr int VertexCount = Cols * 2; // 66
static constexpr int TriangleCount = Segments * 2; // 64

CurvedWindowGeometry::CurvedWindowGeometry(QQuick3DObject *parent)
    : QQuick3DGeometry(parent)
{
    addAttribute(Attribute::PositionSemantic, 0, Attribute::ComponentType::F32Type);
    addAttribute(Attribute::NormalSemantic, 3 * sizeof(float), Attribute::ComponentType::F32Type);
    addAttribute(Attribute::TexCoordSemantic, 6 * sizeof(float), Attribute::ComponentType::F32Type);
    addAttribute(Attribute::IndexSemantic, 0, Attribute::ComponentType::U16Type);

    setPrimitiveType(PrimitiveType::Triangles);
    setStride(sizeof(Vertex));

    m_vertexData.resize(VertexCount * sizeof(Vertex));
    m_indexData.resize(TriangleCount * sizeof(Triangle));

    // Build index buffer (static topology)
    auto *tris = reinterpret_cast<Triangle *>(m_indexData.data());
    for (int j = 0; j < Segments; ++j) {
        const quint16 bl = j;           // bottom row
        const quint16 br = j + 1;
        const quint16 tl = Cols + j;    // top row
        const quint16 tr = Cols + j + 1;
        tris[j * 2 + 0] = {{bl, br, tl}};
        tris[j * 2 + 1] = {{tl, br, tr}};
    }
    setIndexData(m_indexData);

    updateGeometry();
}

float CurvedWindowGeometry::curvature() const
{
    return m_curvature;
}

void CurvedWindowGeometry::setCurvature(float curvature)
{
    curvature = std::clamp(curvature, 0.0f, 6.0f);
    if (qFuzzyCompare(m_curvature, curvature))
        return;
    m_curvature = curvature;
    updateGeometry();
    Q_EMIT curvatureChanged();
}

void CurvedWindowGeometry::updateGeometry()
{
    auto *verts = reinterpret_cast<Vertex *>(m_vertexData.data());

    // The #Rectangle primitive is 100x100 units centered at origin, Y up
    // Bottom row: y = -50, Top row: y = +50
    constexpr float halfSize = 50.0f;

    if (m_curvature < 0.001f) {
        // Flat mesh
        for (int j = 0; j < Cols; ++j) {
            const float u = static_cast<float>(j) / Segments;
            const float x = -halfSize + u * 2.0f * halfSize;

            verts[j] = {{x, -halfSize, 0.0f}, {0.0f, 0.0f, 1.0f}, {u, 0.0f}};
            verts[Cols + j] = {{x, halfSize, 0.0f}, {0.0f, 0.0f, 1.0f}, {u, 1.0f}};
        }
    } else {
        // Concave cylindrical arc
        // R = halfSize / sin(curvature/2) so the chord width stays at 100 units
        const float halfArc = m_curvature / 2.0f;
        const float R = halfSize / std::sin(halfArc);

        for (int j = 0; j < Cols; ++j) {
            const float u = static_cast<float>(j) / Segments;
            const float theta = -halfArc + u * m_curvature;

            const float x = R * std::sin(theta);
            const float z = R * (1.0f - std::cos(theta));

            const QVector3D normal(-std::sin(theta), 0.0f, std::cos(theta));

            verts[j] = {{x, -halfSize, z}, normal, {u, 0.0f}};
            verts[Cols + j] = {{x, halfSize, z}, normal, {u, 1.0f}};
        }
    }

    float minZ = 0.0f, maxZ = 0.0f;
    for (int i = 0; i < VertexCount; ++i) {
        minZ = std::min(minZ, verts[i].position.z());
        maxZ = std::max(maxZ, verts[i].position.z());
    }

    setVertexData(m_vertexData);
    setBounds(QVector3D(-halfSize, -halfSize, minZ), QVector3D(halfSize, halfSize, maxZ));
    update();
}
