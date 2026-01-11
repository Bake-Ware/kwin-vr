/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <KDecoration3/Decoration>
#include <QQuick3DGeometry>

namespace KWin
{

class DecorationGeometry : public QQuick3DGeometry
{
    Q_OBJECT
    Q_PROPERTY(KDecoration3::Decoration *decoration READ decoration WRITE setDecoration NOTIFY decorationChanged)

    QML_ELEMENT
public:
    explicit DecorationGeometry(QQuick3DObject *parent = nullptr);

    KDecoration3::Decoration *decoration() const;
    void setDecoration(KDecoration3::Decoration *decoration);

Q_SIGNALS:
    void decorationChanged();

private:
    void updateGeometry();

    KDecoration3::Decoration *m_decoration = nullptr;
    QByteArray m_vertexData;
};

} // namespace KWin
