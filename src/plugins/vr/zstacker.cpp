/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "zstacker.h"
#include "kwinvr_logging.h"
#include <QMetaProperty>
#include <QQmlProperty>

constexpr auto s_childIndexPropName = "index";
constexpr auto s_childDepthPropName = "itemDepth";
constexpr auto s_childZOffsetPropName = "zOffset";
constexpr auto s_childZOffsetGlobalPropName = "zOffsetGlobal";

QDebug operator<<(QDebug debug, const ZMargins &frame)
{
    QDebugStateSaver saver(debug);
    debug.nospace() << frame.toString();
    return debug;
}

ZStacker::ZStacker(QObject *parent)
    : QObject(parent)
    , m_childIndexProperyName(s_childIndexPropName)
    , m_childIndexProperyNameUtf8(s_childIndexPropName)
    , m_childDepthPropertyName(s_childDepthPropName)
{
    m_timer.setSingleShot(true);
    m_timer.setInterval(0);
    connect(&m_timer, &QTimer::timeout, this, &ZStacker::recomputeLayout);

    m_scheduleRecomputeMeta = staticMetaObject.method(staticMetaObject.indexOfSlot("scheduleRecompute()"));
}

void ZStacker::setTarget(QQuick3DObject *newTarget)
{
    if (m_target == newTarget)
        return;

    if (m_target) {
        disconnect(m_target, &QQuick3DObject::childrenChanged,
                   this, &ZStacker::onChildrenChanged);
        unHookChildren(m_target->childItems());
    }

    m_target = newTarget;

    m_update_connections = false;

    if (m_target) {
        connect(m_target, &QQuick3DObject::childrenChanged,
                this, &ZStacker::onChildrenChanged);
        hookChildren(m_target->childItems());
        scheduleRecompute();
    } else {
        m_timer.stop();
        setDepth(m_initalMargins);
    }

    Q_EMIT targetChanged();
}

void ZStacker::onChildrenChanged()
{
    if (!m_target)
        return;

    m_update_connections = true;
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
    if (parentItem && parentItem == m_target)
        return;

    unHookChild(*child);
    // No need to call scheduleRecompute(), because childrenChanged() signal will be emiited too
}

static std::optional<QMetaMethod> getMetaMethodFromPropertyNotify(QObject *sender, const char *propertyName)
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
        if (!child)
            continue;

        connect(child, &QQuick3DObject::parentChanged, this, &ZStacker::onChildParentChanged, Qt::UniqueConnection);

        connect(child, SIGNAL(itemDepthChanged()),
                this, SLOT(scheduleRecompute()), Qt::UniqueConnection);

        auto indexSignalMeta = getMetaMethodFromPropertyNotify(child, m_childIndexProperyNameUtf8.constData());
        if (indexSignalMeta.has_value()) {
            connect(child, indexSignalMeta.value(), this, m_scheduleRecomputeMeta, Qt::UniqueConnection);
        }
    }
}

void ZStacker::unHookChild(QQuick3DObject &child)
{
    disconnect(&child, &QQuick3DObject::parentChanged, this, &ZStacker::onChildParentChanged);

    disconnect(&child, SIGNAL(itemDepthChanged()),
               this, SLOT(scheduleRecompute()));

    auto indexSignalMeta = getMetaMethodFromPropertyNotify(&child, m_childIndexProperyNameUtf8.constData());
    if (indexSignalMeta) {
        disconnect(&child, indexSignalMeta.value(), this, m_scheduleRecomputeMeta);
    }
}

void ZStacker::unHookChildren(const QList<QQuick3DObject *> &children)
{
    for (auto *child : children) {
        if (!child)
            continue;

        unHookChild(*child);
    }
}

void ZStacker::scheduleRecompute()
{
    startTimerIfNeeded();
}

void ZStacker::startTimerIfNeeded()
{
    if (!m_timer.isActive())
        m_timer.start();
}

void ZStacker::recomputeLayout()
{
    if (!m_target) {
        setDepth(m_initalMargins);
        return;
    }

    auto children = m_target->childItems();
    if (m_update_connections) {
        m_update_connections = false;
        hookChildren(children);
    }

    struct Item
    {
        QQuick3DObject *obj;
        int index;
    };
    QVector<Item> indexed;

    for (auto *child : std::as_const(children)) {
        if (!child)
            continue;
        int idx = -1;
        QVariant v = QQmlProperty::read(child, m_childIndexProperyName);
        if (v.isValid())
            idx = v.toInt();
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

    auto prevZMargins = m_initalMargins;
    for (int i = 0; i != indexed.count(); i++) {
        auto item = indexed[i];
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
    prevZMargins = m_initalMargins;
    for (int i = closestIndexToCenter; i >= 0; i--) {
        auto item = indexed[i];

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
    // totalDepth.flexibleBottom = -targetZOffset + prevZMargins.flexibleBottom;

    setDepth(totalDepth);
}

int ZStacker::centerIndex() const
{
    return m_centerIndex;
}

void ZStacker::setCenterIndex(int newCenterIndex)
{
    if (m_centerIndex == newCenterIndex)
        return;
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

ZMargins ZStacker::initalMargins() const
{
    return m_initalMargins;
}

void ZStacker::setInitalMargins(const ZMargins &newInitalMargins)
{
    if (m_initalMargins == newInitalMargins)
        return;

    m_initalMargins = newInitalMargins;
    scheduleRecompute();
    Q_EMIT initalMarginsChanged();
}

QString ZStacker::childIndexProperyName() const
{
    return m_childIndexProperyName;
}

void ZStacker::setChildIndexProperyName(const QString &newChildIndexProperyName)
{
    if (m_childIndexProperyName == newChildIndexProperyName)
        return;
    m_childIndexProperyName = newChildIndexProperyName;
    m_childIndexProperyNameUtf8 = newChildIndexProperyName.toUtf8();
    scheduleRecompute();
    Q_EMIT childIndexProperyNameChanged();
}

qreal ZStacker::globalOffset() const
{
    return m_globalOffset;
}

void ZStacker::setGlobalOffset(qreal newGlobalOffset)
{
    if (qFuzzyCompare(m_globalOffset, newGlobalOffset))
        return;
    m_globalOffset = newGlobalOffset;
    scheduleRecompute();
    Q_EMIT globalOffsetChanged();
}
