/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "zstacker.h"
#include "kwinvr_logging.h"
#include <QDebug>
#include <QMetaProperty>
#include <QQmlProperty>

#include <climits>

namespace KWin
{

constexpr auto s_childIndexPropName = "index";
constexpr auto s_childDepthPropName = "itemDepth";
constexpr auto s_childZOffsetPropName = "zOffset";
constexpr auto s_childZOffsetGlobalPropName = "zOffsetGlobal";

QDebug operator<<(QDebug debug, const ZMargins &margins)
{
    QDebugStateSaver saver(debug);
    debug.nospace() << margins.toString();
    return debug;
}

ZStacker::ZStacker(QObject *parent)
    : QObject(parent)
    , m_childIndexPropertyName(s_childIndexPropName)
    , m_childIndexPropertyNameUtf8(s_childIndexPropName)
    , m_childDepthPropertyName(s_childDepthPropName)
{
    m_timer.setSingleShot(true);
    m_timer.setInterval(0);
    connect(&m_timer, &QTimer::timeout, this, &ZStacker::recomputeLayout);

    m_scheduleRecomputeMeta = staticMetaObject.method(staticMetaObject.indexOfSlot("scheduleRecompute()"));
}

QQuick3DObject *ZStacker::target() const
{
    return m_target;
}

void ZStacker::setTarget(QQuick3DObject *newTarget)
{
    if (m_target == newTarget) {
        return;
    }

    if (m_target) {
        disconnect(m_target, &QQuick3DObject::childrenChanged,
                   this, &ZStacker::onChildrenChanged);
        unhookChildren(m_target->childItems());
    }

    m_target = newTarget;

    m_updateConnections = false;

    if (m_target) {
        connect(m_target, &QQuick3DObject::childrenChanged,
                this, &ZStacker::onChildrenChanged);
        hookChildren(m_target->childItems());
        scheduleRecompute();
    } else {
        m_timer.stop();
        setDepth(m_initialMargins);
    }

    Q_EMIT targetChanged();
}

void ZStacker::onChildrenChanged()
{
    if (!m_target) {
        return;
    }

    m_updateConnections = true;
    scheduleRecompute();
}

void ZStacker::onChildParentChanged()
{
    QQuick3DObject *child = qobject_cast<QQuick3DObject *>(sender());
    if (!child) {
        qCWarning(KWINVR) << "zStacker: No signal sender when calling onChildParentChanged()";
        return;
    }

    auto parentItem = child->parentItem();
    if (parentItem && parentItem == m_target) {
        return;
    }

    unhookChild(*child);
    // No need to call scheduleRecompute(), because childrenChanged() signal will be emitted too
}

static std::optional<QMetaMethod> notifySignalForProperty(QObject *sender, const char *propertyName)
{
    const QMetaObject *senderMeta = sender->metaObject();
    int propIndex = senderMeta->indexOfProperty(propertyName);
    if (propIndex < 0) {
        return std::nullopt;
    }

    QMetaProperty prop = senderMeta->property(propIndex);
    if (!prop.hasNotifySignal()) {
        return std::nullopt;
    }

    QMetaMethod notify = prop.notifySignal();
    if (!notify.isValid()) {
        return std::nullopt;
    }

    return notify;
}

void ZStacker::hookChildren(const QList<QQuick3DObject *> &children)
{
    for (auto *child : children) {
        if (!child) {
            continue;
        }

        connect(child, &QQuick3DObject::parentChanged, this, &ZStacker::onChildParentChanged, Qt::UniqueConnection);

        connect(child, SIGNAL(itemDepthChanged()),
                this, SLOT(scheduleRecompute()), Qt::UniqueConnection);

        auto indexSignalMeta = notifySignalForProperty(child, m_childIndexPropertyNameUtf8.constData());
        if (indexSignalMeta.has_value()) {
            connect(child, indexSignalMeta.value(), this, m_scheduleRecomputeMeta, Qt::UniqueConnection);
        }
    }
}

void ZStacker::unhookChild(QQuick3DObject &child)
{
    disconnect(&child, &QQuick3DObject::parentChanged, this, &ZStacker::onChildParentChanged);

    disconnect(&child, SIGNAL(itemDepthChanged()),
               this, SLOT(scheduleRecompute()));

    auto indexSignalMeta = notifySignalForProperty(&child, m_childIndexPropertyNameUtf8.constData());
    if (indexSignalMeta) {
        disconnect(&child, indexSignalMeta.value(), this, m_scheduleRecomputeMeta);
    }
}

void ZStacker::unhookChildren(const QList<QQuick3DObject *> &children)
{
    for (auto *child : children) {
        if (!child) {
            continue;
        }

        unhookChild(*child);
    }
}

void ZStacker::scheduleRecompute()
{
    if (!m_timer.isActive()) {
        m_timer.start();
    }
}

void ZStacker::recomputeLayout()
{
    if (!m_target) {
        setDepth(m_initialMargins);
        return;
    }

    auto children = m_target->childItems();
    if (m_updateConnections) {
        m_updateConnections = false;
        hookChildren(children);
    }

    struct Item
    {
        QQuick3DObject *obj;
        int index;
    };
    QList<Item> indexed;
    indexed.reserve(children.size());

    for (auto *child : std::as_const(children)) {
        if (!child) {
            continue;
        }
        int idx = -1;
        QVariant v = QQmlProperty::read(child, m_childIndexPropertyName);
        if (v.isValid()) {
            idx = v.toInt();
        }
        if (idx >= 0) {
            indexed.push_back({child, idx});
        }
    }

    std::sort(indexed.begin(), indexed.end(), [](const Item &a, const Item &b) {
        return a.index < b.index;
    });

    const auto centerIndex = m_centerIndex;
    int closestIndexToCenter = INT_MIN;

    float targetZOffset = 0;

    auto prevZMargins = m_initialMargins;
    for (int i = 0; i != indexed.size(); i++) {
        const auto &item = indexed[i];
        if (item.index < centerIndex) {
            closestIndexToCenter = i;
            continue;
        }

        QVariant itemZMarginsVar = QQmlProperty::read(item.obj, m_childDepthPropertyName);
        if (!itemZMarginsVar.isValid() || !itemZMarginsVar.canConvert<ZMargins>()) {
            continue;
        }
        auto currZMargins = itemZMarginsVar.value<ZMargins>();

        auto flexibleDepth = prevZMargins.flexibleTop + currZMargins.flexibleBottom;
        auto hardDepth = prevZMargins.top + currZMargins.bottom;
        auto effectiveDepth = std::max(flexibleDepth, hardDepth);
        prevZMargins = currZMargins;

        targetZOffset += effectiveDepth;
        QQmlProperty::write(item.obj, s_childZOffsetPropName, targetZOffset);
        QQmlProperty::write(item.obj, s_childZOffsetGlobalPropName, m_globalOffset + targetZOffset);
    }

    ZMargins totalDepth;
    totalDepth.top = targetZOffset + prevZMargins.top;

    targetZOffset = 0;
    prevZMargins = m_initialMargins;
    for (int i = closestIndexToCenter; i >= 0; i--) {
        const auto &item = indexed[i];

        QVariant itemZMarginsVar = QQmlProperty::read(item.obj, m_childDepthPropertyName);
        if (!itemZMarginsVar.isValid() || !itemZMarginsVar.canConvert<ZMargins>()) {
            continue;
        }
        auto currZMargins = itemZMarginsVar.value<ZMargins>();

        auto flexibleDepth = prevZMargins.flexibleBottom + currZMargins.flexibleTop;
        auto hardDepth = prevZMargins.bottom + currZMargins.top;
        auto effectiveDepth = std::max(flexibleDepth, hardDepth);
        prevZMargins = currZMargins;

        targetZOffset -= effectiveDepth;
        QQmlProperty::write(item.obj, s_childZOffsetPropName, targetZOffset);
        QQmlProperty::write(item.obj, s_childZOffsetGlobalPropName, m_globalOffset + targetZOffset);
    }

    totalDepth.bottom = -targetZOffset + prevZMargins.bottom;

    setDepth(totalDepth);
}

int ZStacker::centerIndex() const
{
    return m_centerIndex;
}

void ZStacker::setCenterIndex(int newCenterIndex)
{
    if (m_centerIndex == newCenterIndex) {
        return;
    }
    m_centerIndex = newCenterIndex;
    scheduleRecompute();
    Q_EMIT centerIndexChanged();
}

ZMargins ZStacker::depth() const
{
    return m_depth;
}

void ZStacker::setDepth(const ZMargins &newDepth)
{
    if (m_depth == newDepth) {
        return;
    }
    m_depth = newDepth;
    Q_EMIT depthChanged();
}

ZMargins ZStacker::initialMargins() const
{
    return m_initialMargins;
}

void ZStacker::setInitialMargins(const ZMargins &newInitialMargins)
{
    if (m_initialMargins == newInitialMargins) {
        return;
    }

    m_initialMargins = newInitialMargins;
    scheduleRecompute();
    Q_EMIT initialMarginsChanged();
}

QString ZStacker::childIndexPropertyName() const
{
    return m_childIndexPropertyName;
}

void ZStacker::setChildIndexPropertyName(const QString &newChildIndexPropertyName)
{
    if (m_childIndexPropertyName == newChildIndexPropertyName) {
        return;
    }
    m_childIndexPropertyName = newChildIndexPropertyName;
    m_childIndexPropertyNameUtf8 = newChildIndexPropertyName.toUtf8();
    scheduleRecompute();
    Q_EMIT childIndexPropertyNameChanged();
}

qreal ZStacker::globalOffset() const
{
    return m_globalOffset;
}

void ZStacker::setGlobalOffset(qreal newGlobalOffset)
{
    if (qFuzzyCompare(m_globalOffset, newGlobalOffset)) {
        return;
    }
    m_globalOffset = newGlobalOffset;
    scheduleRecompute();
    Q_EMIT globalOffsetChanged();
}

} // namespace KWin
