/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef ZSTACKER_H
#define ZSTACKER_H

#pragma once

#include <QPointer>
#include <QQuick3DObject>
#include <QTimer>
#include <qdebug.h>

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

    // Comparison operators
    constexpr bool operator==(const ZMargins &other) const noexcept
    {
        // return qFuzzyCompare(top, other.top) && qFuzzyCompare(bottom, other.bottom);
        return qFuzzyCompare(top, other.top) && qFuzzyCompare(bottom, other.bottom)
            && qFuzzyCompare(flexibleTop, other.top) && qFuzzyCompare(flexibleBottom, other.flexibleBottom);
    }

    constexpr bool operator!=(const ZMargins &other) const noexcept
    {
        return !(*this == other);
    }

    // Optional helper for QML
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

/* This class tries to position children of a specified target along Z axis.
 * It works somewhat similar to Row and Column in Qt Quick.
 *
 * Iterates over target's children and reads two properties:
 * index and itemDepth. Then it sets calculated zOffset property for each child.
 *
 * Children can use zOffset property to apply their position around Z axis,
 *
 * For this class to work each child of a specified target should have those three properties defined:
 *
 *   property int index
 *   property real zOffset
 *   property Margins itemDepth
 *
 */
class ZStacker : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QQuick3DObject *target READ target WRITE setTarget NOTIFY targetChanged)

    Q_PROPERTY(int centerIndex READ centerIndex WRITE setCenterIndex NOTIFY centerIndexChanged FINAL)

    Q_PROPERTY(ZMargins initalMargins READ initalMargins WRITE setInitalMargins NOTIFY initalMarginsChanged FINAL)
    Q_PROPERTY(ZMargins depth READ depth NOTIFY depthChanged FINAL)

    Q_PROPERTY(qreal globalOffset READ globalOffset WRITE setGlobalOffset NOTIFY globalOffsetChanged FINAL)

    /* By default this is "index" */
    Q_PROPERTY(QString childIndexProperyName READ childIndexProperyName WRITE setChildIndexProperyName NOTIFY childIndexProperyNameChanged FINAL)

    QML_ELEMENT
public:
    explicit ZStacker(QObject *parent = nullptr);

    QQuick3DObject *target() const
    {
        return m_target;
    }
    void setTarget(QQuick3DObject *newTarget);

    int centerIndex() const;
    void setCenterIndex(int newCenterIndex);

    ZMargins depth() const;
    ZMargins initalMargins() const;
    void setInitalMargins(const ZMargins &newInitalMargins);

    QString childIndexProperyName() const;
    void setChildIndexProperyName(const QString &newChildIndexProperyName);

    qreal globalOffset() const;
    void setGlobalOffset(qreal newGlobalOffset);

Q_SIGNALS:
    void targetChanged();
    void centerIndexChanged();
    void depthChanged();
    void initalMarginsChanged();
    void childIndexProperyNameChanged();
    void globalOffsetChanged();

private Q_SLOTS:
    void onChildrenChanged();
    void onChildParentChanged();
    void scheduleRecompute();
    void recomputeLayout();

private:
    void hookChildren(const QList<QQuick3DObject *> &children);
    void unHookChild(QQuick3DObject &child);
    void unHookChildren(const QList<QQuick3DObject *> &children);
    void startTimerIfNeeded();

    void setDepth(const ZMargins &newDepth);

    QPointer<QQuick3DObject> m_target;
    QTimer m_timer;
    int m_centerIndex = 0;
    ZMargins m_depth;
    ZMargins m_initalMargins;
    QString m_childIndexProperyName;
    QByteArray m_childIndexProperyNameUtf8;
    QString m_childDepthPropertyName;

    QMetaMethod m_scheduleRecomputeMeta;
    bool m_update_connections = false;
    qreal m_globalOffset = 0;
};

#endif // MYROWWATCHER_H
