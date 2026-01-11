/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QVector2D>
#include <QVector3D>
#include <QtGlobal>

namespace KWin
{

// Layout for the vertex buffer using Qt types
struct Vertex
{
    QVector3D position;
    QVector3D normal;
    QVector2D texCoord;
};
static_assert(sizeof(Vertex) == 32, "Vertex struct size mismatch");

struct VertexQuad
{
    Vertex tl;
    Vertex bl;
    Vertex tr;
    Vertex br;
};
static_assert(sizeof(VertexQuad) == sizeof(Vertex) * 4, "VertexQuad struct size mismatch");

// Layout for the index buffer
struct Triangle
{
    quint16 indices[3];
};
struct Quad
{
    Triangle triangles[2];
};

static_assert(sizeof(Triangle) == sizeof(quint16) * 3, "Triangle struct size mismatch");
static_assert(sizeof(Quad) == sizeof(Triangle) * 2, "Quad struct size mismatch");

inline void setQuad(VertexQuad *q, float xMin, float xMax, float yMin, float yMax,
                    float uMin, float uMax, float vMin, float vMax)
{
    q->tl = {{xMin, yMax, 0.0f}, {0.0f, 0.0f, 1.0f}, {uMin, vMax}};
    q->bl = {{xMin, yMin, 0.0f}, {0.0f, 0.0f, 1.0f}, {uMin, vMin}};
    q->tr = {{xMax, yMax, 0.0f}, {0.0f, 0.0f, 1.0f}, {uMax, vMax}};
    q->br = {{xMax, yMin, 0.0f}, {0.0f, 0.0f, 1.0f}, {uMax, vMin}};
}

}
