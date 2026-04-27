/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "layoutmodes/ilayoutmode.h"
#include "zmargins.h"

#include <QPointer>
#include <QQuick3DObject>
#include <QTimer>

#include <memory>
#include <unordered_map>

namespace KWin
{

/**
 * Volumetric layout primitive. Positions children of `target` in 3D space
 * according to the configured `mode`. Strategy pattern: each Mode is an
 * ILayoutMode implementation. Phase A ships only Stack mode (Z-only,
 * bit-identical to the prior ZStacker behaviour).
 *
 * Children expose:
 *   property int <childIndexPropertyName>   // sort key; default "index"
 *   property zMargins itemDepth             // Z thickness
 *
 * Stacker writes per child:
 *   zOffset, zOffsetGlobal                  // local + global Z position
 */
class VolumetricStacker : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QQuick3DObject *target READ target WRITE setTarget NOTIFY targetChanged)
    Q_PROPERTY(int centerIndex READ centerIndex WRITE setCenterIndex NOTIFY centerIndexChanged FINAL)
    Q_PROPERTY(ZMargins initialMargins READ initialMargins WRITE setInitialMargins NOTIFY initialMarginsChanged FINAL)
    Q_PROPERTY(ZMargins depth READ depth NOTIFY depthChanged FINAL)
    Q_PROPERTY(qreal globalOffset READ globalOffset WRITE setGlobalOffset NOTIFY globalOffsetChanged FINAL)
    Q_PROPERTY(QString childIndexPropertyName READ childIndexPropertyName WRITE setChildIndexPropertyName NOTIFY childIndexPropertyNameChanged FINAL)
    Q_PROPERTY(Mode mode READ mode WRITE setMode NOTIFY modeChanged FINAL)
    QML_ELEMENT

public:
    enum Mode {
        Stack = 0,
        // Cascade, SnapRow, Free, OcclusionAware land in later phases.
    };
    Q_ENUM(Mode)

    explicit VolumetricStacker(QObject *parent = nullptr);
    ~VolumetricStacker() override;

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

    Mode mode() const;
    void setMode(Mode newMode);

Q_SIGNALS:
    void targetChanged();
    void centerIndexChanged();
    void depthChanged();
    void initialMarginsChanged();
    void childIndexPropertyNameChanged();
    void globalOffsetChanged();
    void modeChanged();

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

    ILayoutMode *modeImpl() const;

    QPointer<QQuick3DObject> m_target;
    QTimer m_timer;
    int m_centerIndex = 0;
    ZMargins m_depth;
    ZMargins m_initialMargins;
    QString m_childIndexPropertyName;
    QByteArray m_childIndexPropertyNameUtf8;
    QString m_childDepthPropertyName;
    Mode m_mode = Mode::Stack;
    std::unordered_map<int, std::unique_ptr<ILayoutMode>> m_modes;

    QMetaMethod m_scheduleRecomputeMeta;
    bool m_updateConnections = false;
    qreal m_globalOffset = 0;
};

} // namespace KWin
