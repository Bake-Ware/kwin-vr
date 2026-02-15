/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QQuick3DGeometry>

namespace KWin
{

class CurvedWindowGeometry : public QQuick3DGeometry
{
    Q_OBJECT
    Q_PROPERTY(float curvature READ curvature WRITE setCurvature NOTIFY curvatureChanged)

    QML_ELEMENT
public:
    explicit CurvedWindowGeometry(QQuick3DObject *parent = nullptr);

    float curvature() const;
    void setCurvature(float curvature);

Q_SIGNALS:
    void curvatureChanged();

private:
    void updateGeometry();

    float m_curvature = 0.0f;
    QByteArray m_vertexData;
    QByteArray m_indexData;
};

}
