/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "volumetricstacker.h"
#include "kwinvr_logging.h"
#include "layoutmodes/stackmode.h"

#include <QDebug>
#include <QMetaProperty>
#include <QQmlProperty>

#include <optional>

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

VolumetricStacker::VolumetricStacker(QObject *parent)
    : QObject(parent)
    , m_childIndexPropertyName(s_childIndexPropName)
    , m_childIndexPropertyNameUtf8(s_childIndexPropName)
    , m_childDepthPropertyName(s_childDepthPropName)
{
    m_timer.setSingleShot(true);
    m_timer.setInterval(0);
    connect(&m_timer, &QTimer::timeout, this, &VolumetricStacker::recomputeLayout);

    m_scheduleRecomputeMeta = staticMetaObject.method(staticMetaObject.indexOfSlot("scheduleRecompute()"));

    m_modes[Mode::Stack] = std::make_unique<StackMode>();
}

VolumetricStacker::~VolumetricStacker() = default;

ILayoutMode *VolumetricStacker::modeImpl() const
{
    auto it = m_modes.find(m_mode);
    return it != m_modes.end() ? it->second.get() : nullptr;
}

QQuick3DObject *VolumetricStacker::target() const
{
    return m_target;
}

void VolumetricStacker::setTarget(QQuick3DObject *newTarget)
{
    if (m_target == newTarget) {
        return;
    }

    if (m_target) {
        disconnect(m_target, &QQuick3DObject::childrenChanged,
                   this, &VolumetricStacker::onChildrenChanged);
        unhookChildren(m_target->childItems());
    }

    m_target = newTarget;
    m_updateConnections = false;

    if (m_target) {
        connect(m_target, &QQuick3DObject::childrenChanged,
                this, &VolumetricStacker::onChildrenChanged);
        hookChildren(m_target->childItems());
        scheduleRecompute();
    } else {
        m_timer.stop();
        setDepth(m_initialMargins);
    }

    Q_EMIT targetChanged();
}

void VolumetricStacker::onChildrenChanged()
{
    if (!m_target) {
        return;
    }
    m_updateConnections = true;
    scheduleRecompute();
}

void VolumetricStacker::onChildParentChanged()
{
    QQuick3DObject *child = qobject_cast<QQuick3DObject *>(sender());
    if (!child) {
        qCWarning(KWINVR) << "VolumetricStacker: No signal sender when calling onChildParentChanged()";
        return;
    }

    auto parentItem = child->parentItem();
    if (parentItem && parentItem == m_target) {
        return;
    }

    unhookChild(*child);
    // No need to call scheduleRecompute(): childrenChanged() signal will be emitted too.
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

void VolumetricStacker::hookChildren(const QList<QQuick3DObject *> &children)
{
    for (auto *child : children) {
        if (!child) {
            continue;
        }

        connect(child, &QQuick3DObject::parentChanged, this, &VolumetricStacker::onChildParentChanged, Qt::UniqueConnection);

        connect(child, SIGNAL(itemDepthChanged()),
                this, SLOT(scheduleRecompute()), Qt::UniqueConnection);

        auto indexSignalMeta = notifySignalForProperty(child, m_childIndexPropertyNameUtf8.constData());
        if (indexSignalMeta.has_value()) {
            connect(child, indexSignalMeta.value(), this, m_scheduleRecomputeMeta, Qt::UniqueConnection);
        }
    }
}

void VolumetricStacker::unhookChild(QQuick3DObject &child)
{
    disconnect(&child, &QQuick3DObject::parentChanged, this, &VolumetricStacker::onChildParentChanged);

    disconnect(&child, SIGNAL(itemDepthChanged()),
               this, SLOT(scheduleRecompute()));

    auto indexSignalMeta = notifySignalForProperty(&child, m_childIndexPropertyNameUtf8.constData());
    if (indexSignalMeta) {
        disconnect(&child, indexSignalMeta.value(), this, m_scheduleRecomputeMeta);
    }
}

void VolumetricStacker::unhookChildren(const QList<QQuick3DObject *> &children)
{
    for (auto *child : children) {
        if (!child) {
            continue;
        }
        unhookChild(*child);
    }
}

void VolumetricStacker::scheduleRecompute()
{
    if (!m_timer.isActive()) {
        m_timer.start();
    }
}

void VolumetricStacker::recomputeLayout()
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

    QList<LayoutItem> items;
    items.reserve(children.size());

    for (auto *child : std::as_const(children)) {
        if (!child) {
            continue;
        }
        QVariant idxVar = QQmlProperty::read(child, m_childIndexPropertyName);
        if (!idxVar.isValid()) {
            continue;
        }
        const int idx = idxVar.toInt();
        if (idx < 0) {
            continue;
        }
        QVariant depthVar = QQmlProperty::read(child, m_childDepthPropertyName);
        ZMargins depth;
        if (depthVar.isValid() && depthVar.canConvert<ZMargins>()) {
            depth = depthVar.value<ZMargins>();
        }
        items.append(LayoutItem{child, idx, 0, depth, QSizeF{}, -1});
    }

    ILayoutMode *mode = modeImpl();
    if (!mode) {
        qCWarning(KWINVR) << "VolumetricStacker: no mode impl for" << m_mode;
        setDepth(m_initialMargins);
        return;
    }

    LayoutResult result = mode->apply(items, m_initialMargins, m_centerIndex);

    for (auto it = result.placements.constBegin(); it != result.placements.constEnd(); ++it) {
        QQuick3DObject *obj = it.key();
        const LayoutOutput &out = it.value();
        QQmlProperty::write(obj, s_childZOffsetPropName, out.zOffset);
        QQmlProperty::write(obj, s_childZOffsetGlobalPropName, m_globalOffset + out.zOffset);
    }

    setDepth(result.totalDepth);
}

int VolumetricStacker::centerIndex() const
{
    return m_centerIndex;
}

void VolumetricStacker::setCenterIndex(int newCenterIndex)
{
    if (m_centerIndex == newCenterIndex) {
        return;
    }
    m_centerIndex = newCenterIndex;
    scheduleRecompute();
    Q_EMIT centerIndexChanged();
}

ZMargins VolumetricStacker::depth() const
{
    return m_depth;
}

void VolumetricStacker::setDepth(const ZMargins &newDepth)
{
    if (m_depth == newDepth) {
        return;
    }
    m_depth = newDepth;
    Q_EMIT depthChanged();
}

ZMargins VolumetricStacker::initialMargins() const
{
    return m_initialMargins;
}

void VolumetricStacker::setInitialMargins(const ZMargins &newInitialMargins)
{
    if (m_initialMargins == newInitialMargins) {
        return;
    }

    m_initialMargins = newInitialMargins;
    scheduleRecompute();
    Q_EMIT initialMarginsChanged();
}

QString VolumetricStacker::childIndexPropertyName() const
{
    return m_childIndexPropertyName;
}

void VolumetricStacker::setChildIndexPropertyName(const QString &newChildIndexPropertyName)
{
    if (m_childIndexPropertyName == newChildIndexPropertyName) {
        return;
    }
    m_childIndexPropertyName = newChildIndexPropertyName;
    m_childIndexPropertyNameUtf8 = newChildIndexPropertyName.toUtf8();
    scheduleRecompute();
    Q_EMIT childIndexPropertyNameChanged();
}

qreal VolumetricStacker::globalOffset() const
{
    return m_globalOffset;
}

void VolumetricStacker::setGlobalOffset(qreal newGlobalOffset)
{
    if (qFuzzyCompare(m_globalOffset, newGlobalOffset)) {
        return;
    }
    m_globalOffset = newGlobalOffset;
    scheduleRecompute();
    Q_EMIT globalOffsetChanged();
}

VolumetricStacker::Mode VolumetricStacker::mode() const
{
    return m_mode;
}

void VolumetricStacker::setMode(Mode newMode)
{
    if (m_mode == newMode) {
        return;
    }
    m_mode = newMode;
    scheduleRecompute();
    Q_EMIT modeChanged();
}

} // namespace KWin
