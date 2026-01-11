/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "decorationgeometry.h"
#include "geometrytypes.h"
#include "kwinvr_logging.h"
#include <KDecoration3/DecoratedWindow>
#include <QVector2D>
#include <QVector3D>

#include <cstring>

namespace KWin
{

static const QByteArray indices = [] {
    const Quad quads[4] = {
        {{{0, 1, 2}, {2, 1, 3}}}, // Top
        {{{4, 5, 6}, {6, 5, 7}}}, // Bottom
        {{{8, 9, 10}, {10, 9, 11}}}, // Left
        {{{12, 13, 14}, {14, 13, 15}}} // Right
    };
    return QByteArray(reinterpret_cast<const char *>(quads), sizeof(quads));
}();

KDecoration3::Decoration *DecorationGeometry::decoration() const
{
    return m_decoration;
}

DecorationGeometry::DecorationGeometry(QQuick3DObject *parent)
    : QQuick3DGeometry(parent)
{
    addAttribute(Attribute::PositionSemantic, 0, Attribute::ComponentType::F32Type);
    addAttribute(Attribute::NormalSemantic, 3 * sizeof(float), Attribute::ComponentType::F32Type);
    addAttribute(Attribute::TexCoordSemantic, 6 * sizeof(float), Attribute::ComponentType::F32Type);
    addAttribute(Attribute::IndexSemantic, 0, Attribute::ComponentType::U16Type);

    setIndexData(indices);
    setPrimitiveType(PrimitiveType::Triangles);

    m_vertexData.resize(4 * sizeof(VertexQuad));
    setStride(sizeof(Vertex));
}

void DecorationGeometry::setDecoration(KDecoration3::Decoration *decoration)
{
    if (m_decoration == decoration) {
        return;
    }

    if (m_decoration) {
        disconnect(m_decoration, &KDecoration3::Decoration::bordersChanged, this, &DecorationGeometry::updateGeometry);
        disconnect(m_decoration, &KDecoration3::Decoration::resizeOnlyBordersChanged, this, &DecorationGeometry::updateGeometry);
        auto window = m_decoration->window();
        if (window) {
            disconnect(window, &KDecoration3::DecoratedWindow::sizeChanged, this, &DecorationGeometry::updateGeometry);
        }
    }

    m_decoration = decoration;

    if (m_decoration) {
        connect(m_decoration, &KDecoration3::Decoration::bordersChanged, this, &DecorationGeometry::updateGeometry);
        connect(m_decoration, &KDecoration3::Decoration::resizeOnlyBordersChanged, this, &DecorationGeometry::updateGeometry);
        auto window = m_decoration->window();

        if (window) {
            connect(window, &KDecoration3::DecoratedWindow::sizeChanged, this, &DecorationGeometry::updateGeometry);
            connect(window, &QObject::destroyed, this, [this]() {
                setDecoration(nullptr);
            });
        } else {
            qCWarning(KWINVR) << "Decoration has no window, how is that possible?";
        }

        connect(m_decoration, &QObject::destroyed, this, [this]() {
            setDecoration(nullptr);
        });
    }
    updateGeometry();
    Q_EMIT decorationChanged();
}

void DecorationGeometry::updateGeometry()
{
    const QSizeF texSize = m_decoration ? m_decoration->size() : QSizeF();
    if (texSize.isEmpty()) {
        m_vertexData.fill(0);
        setVertexData(m_vertexData);
        update();
        return;
    }

    const float bl = static_cast<float>(m_decoration->borderLeft());
    const float br = static_cast<float>(m_decoration->borderRight());
    const float bt = static_cast<float>(m_decoration->borderTop());
    const float bb = static_cast<float>(m_decoration->borderBottom());

    // Use pure pixel coordinates. Scaling is handled by the Node.
    const float w = static_cast<float>(texSize.width());
    const float h = static_cast<float>(texSize.height());

    // UV normalization factors
    const float iTexW = 1.0f / w;
    const float iTexH = 1.0f / h;

    VertexQuad stackQuads[4];

    const float hW = w / 2.0f;
    const float hH = h / 2.0f;

    const float u1 = bl * iTexW;
    const float u2 = 1.0f - (br * iTexW);
    const float v1 = 1.0f - (bt * iTexH);
    const float v2 = bb * iTexH;

    // 1. Top Bar
    setQuad(&stackQuads[0], -hW, hW, hH - bt, hH, 0.0f, 1.0f, v1, 1.0f);
    // 2. Bottom Bar
    setQuad(&stackQuads[1], -hW, hW, -hH, -hH + bb, 0.0f, 1.0f, 0.0f, v2);
    // 3. Left Bar (Connects top and bottom)
    setQuad(&stackQuads[2], -hW, -hW + bl, -hH + bb, hH - bt, 0.0f, u1, v2, v1);
    // 4. Right Bar (Connects top and bottom)
    setQuad(&stackQuads[3], hW - br, hW, -hH + bb, hH - bt, u2, 1.0f, v2, v1);

    std::memcpy(m_vertexData.data(), stackQuads, sizeof(stackQuads));

    setVertexData(m_vertexData);
    setBounds(QVector3D(-hW, -hH, -0.01f), QVector3D(hW, hH, 0.01f));
    update();
}

} // namespace KWin
