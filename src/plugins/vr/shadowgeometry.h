/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KDecoration3/DecorationShadow>
#include <QQuick3DGeometry>

namespace KWin
{

class ShadowGeometry : public QQuick3DGeometry
{
    Q_OBJECT
    Q_PROPERTY(KDecoration3::DecorationShadow *shadow READ shadow WRITE setShadow NOTIFY shadowChanged)
    Q_PROPERTY(float width READ width WRITE setWidth NOTIFY sizeChanged)
    Q_PROPERTY(float height READ height WRITE setHeight NOTIFY sizeChanged)

    QML_ELEMENT
public:
    explicit ShadowGeometry(QQuick3DObject *parent = nullptr);

    KDecoration3::DecorationShadow *shadow() const;
    void setShadow(KDecoration3::DecorationShadow *shadow);

    float width() const;
    void setWidth(float newWidth);

    float height() const;
    void setHeight(float newHeight);

Q_SIGNALS:
    void shadowChanged();
    void sizeChanged();

private:
    void updateGeometry();

    KDecoration3::DecorationShadow *m_shadow = nullptr;
    float m_width = 100.0f;
    float m_height = 100.0f;

    // Cached vertex buffer to avoid allocations
    QByteArray m_vertexData;
};

} // namespace KWin
