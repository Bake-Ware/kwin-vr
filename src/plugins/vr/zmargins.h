/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QString>
#include <QtCore/qobject.h>
#include <QtQml/qqmlregistration.h>

namespace KWin
{

struct ZMargins
{
    Q_GADGET
    Q_PROPERTY(float top MEMBER top)
    Q_PROPERTY(float bottom MEMBER bottom)
    Q_PROPERTY(float flexibleTop MEMBER flexibleTop)
    Q_PROPERTY(float flexibleBottom MEMBER flexibleBottom)
    QML_VALUE_TYPE(zMargins)
    QML_STRUCTURED_VALUE
public:
    constexpr ZMargins() = default;
    constexpr ZMargins(float top, float bottom)
        : top(top)
        , bottom(bottom)
    {
    }

    bool operator==(const ZMargins &other) const noexcept
    {
        return qFuzzyCompare(top, other.top) && qFuzzyCompare(bottom, other.bottom)
            && qFuzzyCompare(flexibleTop, other.flexibleTop) && qFuzzyCompare(flexibleBottom, other.flexibleBottom);
    }

    Q_INVOKABLE bool equals(const ZMargins &other) const noexcept
    {
        return *this == other;
    }

    Q_INVOKABLE double depth() const
    {
        return top + bottom;
    }

    Q_INVOKABLE QString toString() const
    {
        return QStringLiteral("ZMargins(top=%1[%3], bottom=%2[%4])").arg(top).arg(bottom).arg(flexibleTop).arg(flexibleBottom);
    }

    float top = 0;
    float bottom = 0;
    float flexibleTop = 0;
    float flexibleBottom = 0;
};

} // namespace KWin
