/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QPointer>
#include <QQuick3DObject>
#include <QTimer>

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

/**
 * Positions children of a specified target along the Z axis,
 * similar to Row and Column in Qt Quick.
 *
 * Iterates over target's children and reads two properties:
 * index and itemDepth. Then it sets the calculated zOffset property for each child.
 *
 * Children can use zOffset property to apply their position around Z axis.
 *
 * For this class to work each child of a specified target should have
 * these three properties defined:
 * @code
 *   property int index
 *   property real zOffset
 *   property ZMargins itemDepth
 * @endcode
 */
class ZStacker : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QQuick3DObject *target READ target WRITE setTarget NOTIFY targetChanged)
    Q_PROPERTY(int centerIndex READ centerIndex WRITE setCenterIndex NOTIFY centerIndexChanged FINAL)
    Q_PROPERTY(ZMargins initialMargins READ initialMargins WRITE setInitialMargins NOTIFY initialMarginsChanged FINAL)
    Q_PROPERTY(ZMargins depth READ depth NOTIFY depthChanged FINAL)
    Q_PROPERTY(qreal globalOffset READ globalOffset WRITE setGlobalOffset NOTIFY globalOffsetChanged FINAL)
    Q_PROPERTY(QString childIndexPropertyName READ childIndexPropertyName WRITE setChildIndexPropertyName NOTIFY childIndexPropertyNameChanged FINAL)

    QML_ELEMENT
public:
    explicit ZStacker(QObject *parent = nullptr);

    QQuick3DObject *target() const;
    void setTarget(QQuick3DObject *newTarget);

    int centerIndex() const;
    void setCenterIndex(int newCenterIndex);

    ZMargins depth() const;
    ZMargins initialMargins() const;
    void setInitialMargins(const ZMargins &newInitialMargins);

    QString childIndexPropertyName() const;
    void setChildIndexPropertyName(const QString &newChildIndexPropertyName);

    qreal globalOffset() const;
    void setGlobalOffset(qreal newGlobalOffset);

Q_SIGNALS:
    void targetChanged();
    void centerIndexChanged();
    void depthChanged();
    void initialMarginsChanged();
    void childIndexPropertyNameChanged();
    void globalOffsetChanged();

private Q_SLOTS:
    void scheduleRecompute();

private:
    void onChildrenChanged();
    void onChildParentChanged();
    void recomputeLayout();
    void hookChildren(const QList<QQuick3DObject *> &children);
    void unhookChild(QQuick3DObject &child);
    void unhookChildren(const QList<QQuick3DObject *> &children);

    void setDepth(const ZMargins &newDepth);

    QPointer<QQuick3DObject> m_target;
    QTimer m_timer;
    int m_centerIndex = 0;
    ZMargins m_depth;
    ZMargins m_initialMargins;
    QString m_childIndexPropertyName;
    QByteArray m_childIndexPropertyNameUtf8;
    QString m_childDepthPropertyName;

    QMetaMethod m_scheduleRecomputeMeta;
    bool m_updateConnections = false;
    qreal m_globalOffset = 0;
};

} // namespace KWin
