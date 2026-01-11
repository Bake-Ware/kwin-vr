/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "shadowgeometry.h"
#include "geometrytypes.h"
#include <QVector2D>
#include <QVector3D>

#include <cstring>

namespace KWin
{

// 8 Quads: TL, T, TR, L, R, BL, B, BR
static const QByteArray indices = [] {
    const Quad quads[8] = {
        {{{0, 1, 2}, {2, 1, 3}}}, // 0: Top-Left
        {{{4, 5, 6}, {6, 5, 7}}}, // 1: Top
        {{{8, 9, 10}, {10, 9, 11}}}, // 2: Top-Right
        {{{12, 13, 14}, {14, 13, 15}}}, // 3: Left
        {{{16, 17, 18}, {18, 17, 19}}}, // 4: Right
        {{{20, 21, 22}, {22, 21, 23}}}, // 5: Bottom-Left
        {{{24, 25, 26}, {26, 25, 27}}}, // 6: Bottom
        {{{28, 29, 30}, {30, 29, 31}}} // 7: Bottom-Right
    };
    return QByteArray(reinterpret_cast<const char *>(quads), sizeof(quads));
}();

ShadowGeometry::ShadowGeometry(QQuick3DObject *parent)
    : QQuick3DGeometry(parent)
{
    addAttribute(Attribute::PositionSemantic, 0, Attribute::ComponentType::F32Type);
    addAttribute(Attribute::NormalSemantic, 3 * sizeof(float), Attribute::ComponentType::F32Type);
    addAttribute(Attribute::TexCoordSemantic, 6 * sizeof(float), Attribute::ComponentType::F32Type);
    addAttribute(Attribute::IndexSemantic, 0, Attribute::ComponentType::U16Type);

    setIndexData(indices);
    setPrimitiveType(PrimitiveType::Triangles);

    m_vertexData.resize(8 * sizeof(VertexQuad));
    setStride(sizeof(Vertex));
}

KDecoration3::DecorationShadow *ShadowGeometry::shadow() const
{
    return m_shadow;
}

void ShadowGeometry::setShadow(KDecoration3::DecorationShadow *shadow)
{
    if (m_shadow == shadow) {
        return;
    }

    if (m_shadow) {
        disconnect(m_shadow, nullptr, this, nullptr);
    }
    m_shadow = shadow;
    if (m_shadow) {
        connect(m_shadow, &KDecoration3::DecorationShadow::innerShadowRectChanged, this, &ShadowGeometry::updateGeometry);
        connect(m_shadow, &KDecoration3::DecorationShadow::paddingChanged, this, &ShadowGeometry::updateGeometry);
        connect(m_shadow, &KDecoration3::DecorationShadow::shadowChanged, this, &ShadowGeometry::updateGeometry);
        connect(m_shadow, &QObject::destroyed, this, [this]() {
            setShadow(nullptr);
        });
    }
    updateGeometry();
    Q_EMIT shadowChanged();
}

float ShadowGeometry::width() const
{
    return m_width;
}

void ShadowGeometry::setWidth(float newWidth)
{
    if (qFuzzyCompare(m_width, newWidth)) {
        return;
    }
    m_width = newWidth;
    updateGeometry();
    Q_EMIT sizeChanged();
}

float ShadowGeometry::height() const
{
    return m_height;
}

void ShadowGeometry::setHeight(float newHeight)
{
    if (qFuzzyCompare(m_height, newHeight)) {
        return;
    }
    m_height = newHeight;
    updateGeometry();
    Q_EMIT sizeChanged();
}

void ShadowGeometry::updateGeometry()
{
    if (!m_shadow || m_shadow->shadow().isNull() || m_width <= 0 || m_height <= 0) {
        m_vertexData.fill(0);
        setVertexData(m_vertexData);
        update();
        return;
    }

    const QImage img = m_shadow->shadow();
    const QRectF inner = m_shadow->innerShadowRect();
    const QSize texSize = img.size();

    if (texSize.isEmpty()) {
        return;
    }

    const float dpr = static_cast<float>(img.devicePixelRatio());

    // Padding values (visible area outside window)
    const float pl = static_cast<float>(m_shadow->paddingLeft());
    const float pt = static_cast<float>(m_shadow->paddingTop());
    const float pr = static_cast<float>(m_shadow->paddingRight());
    const float pb = static_cast<float>(m_shadow->paddingBottom());

    // 1:1 Mapping Logic
    // We map the texture elements 1:1 to geometry pixels.
    // This allows the shadow to overlap "behind" the window if the element is larger than padding.
    // This fixes the "Gap" (by drawing the overlap) and "Squashed Corners" (by using correct aspect ratio).

    // Texture Element Sizes (Physical)
    const float leftElemW = static_cast<float>(inner.left()) * dpr;
    const float rightElemW = static_cast<float>(texSize.width() - inner.right()) * dpr;
    const float topElemH = static_cast<float>(inner.top()) * dpr;
    const float bottomElemH = static_cast<float>(texSize.height() - inner.bottom()) * dpr;

    const float w = static_cast<float>(texSize.width());
    const float h = static_cast<float>(texSize.height());

    // UVs
    float u0 = 0.0f;
    float u1 = leftElemW / w;
    float u2 = 1.0f - (rightElemW / w);
    float u3 = 1.0f;

    float v0 = 1.0f;
    float v1 = 1.0f - (topElemH / h);
    float v2 = bottomElemH / h;
    float v3 = 0.0f;

    // Positions (Centered around 0,0)
    // x0 is the outer edge (window edge - padding)
    // x1 is x0 + leftElemW

    float x0 = -m_width / 2.0f - pl;
    float x1 = x0 + leftElemW;

    float x3 = m_width / 2.0f + pr;
    float x2 = x3 - rightElemW;

    float y0 = m_height / 2.0f + pt;
    float y1 = y0 - topElemH;

    float y3 = -m_height / 2.0f - pb;
    float y2 = y3 + bottomElemH;

    // Clamp to prevent quad inversion when window is smaller than shadow elements
    if (x1 > x2) {
        float mid = (x1 + x2) / 2.0f;
        x1 = x2 = mid;
    }
    if (y2 > y1) {
        float mid = (y1 + y2) / 2.0f;
        y1 = y2 = mid;
    }

    VertexQuad stackQuads[8];

    // 0: Top-Left
    setQuad(&stackQuads[0], x0, x1, y1, y0, u0, u1, v1, v0);
    // 1: Top
    setQuad(&stackQuads[1], x1, x2, y1, y0, u1, u2, v1, v0);
    // 2: Top-Right
    setQuad(&stackQuads[2], x2, x3, y1, y0, u2, u3, v1, v0);
    // 3: Left
    setQuad(&stackQuads[3], x0, x1, y2, y1, u0, u1, v2, v1);
    // 4: Right
    setQuad(&stackQuads[4], x2, x3, y2, y1, u2, u3, v2, v1);
    // 5: Bottom-Left
    setQuad(&stackQuads[5], x0, x1, y3, y2, u0, u1, v3, v2);
    // 6: Bottom
    setQuad(&stackQuads[6], x1, x2, y3, y2, u1, u2, v3, v2);
    // 7: Bottom-Right
    setQuad(&stackQuads[7], x2, x3, y3, y2, u2, u3, v3, v2);

    std::memcpy(m_vertexData.data(), stackQuads, sizeof(stackQuads));

    setVertexData(m_vertexData);
    setBounds(QVector3D(x0, y3, -0.01f), QVector3D(x3, y0, 0.01f));
    update();
}

} // namespace KWin
