/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QList>
#include <QObject>
#include <QVector3D>
#include <QtQmlIntegration>
#include <QtQuick3D/private/qquick3dnode_p.h>

namespace KWin
{

struct AngularBounds
{
    qreal minAzimuth, maxAzimuth;
    qreal minElevation, maxElevation;
};

/**
 * SpaceAllocator3D finds free positions in 3D space using spherical projection.
 *
 * Objects are projected onto a sphere around the viewpoint. The allocator checks
 * for overlap in angular space (azimuth/elevation) to prevent occlusion - new
 * objects are placed where they won't be hidden behind existing objects.
 */
class SpaceAllocator3D : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QQuick3DNode *viewpoint READ viewpoint WRITE setViewpoint NOTIFY viewpointChanged FINAL)
    Q_PROPERTY(qreal distance READ distance WRITE setDistance NOTIFY distanceChanged FINAL)
    Q_PROPERTY(qreal spacing READ spacing WRITE setSpacing NOTIFY spacingChanged FINAL)
    Q_PROPERTY(QString sizePropertyName READ sizePropertyName WRITE setSizePropertyName NOTIFY sizePropertyNameChanged FINAL)
    Q_PROPERTY(qreal searchGranularity READ searchGranularity WRITE setSearchGranularity NOTIFY searchGranularityChanged FINAL)
    QML_ELEMENT

public:
    explicit SpaceAllocator3D(QObject *parent = nullptr);

    QQuick3DNode *viewpoint() const;
    void setViewpoint(QQuick3DNode *node);

    qreal distance() const;
    void setDistance(qreal d);

    qreal spacing() const;
    void setSpacing(qreal s);

    QString sizePropertyName() const;
    void setSizePropertyName(const QString &name);

    qreal searchGranularity() const;
    void setSearchGranularity(qreal granularity);

    Q_INVOKABLE QVector3D findFreePosition(qreal width, qreal height);
    Q_INVOKABLE void registerObject(QQuick3DNode *object);
    Q_INVOKABLE void unregisterObject(QQuick3DNode *object);
    Q_INVOKABLE QVariantList debugGetSpherePoints(qreal angularStep, qreal maxAngle);

Q_SIGNALS:
    void viewpointChanged();
    void distanceChanged();
    void spacingChanged();
    void sizePropertyNameChanged();
    void searchGranularityChanged();

private:
    struct ViewBasis
    {
        QVector3D position;
        QVector3D forward;
        QVector3D right;
        QVector3D up;
    };

    ViewBasis viewBasis() const;
    AngularBounds projectToAngular(QQuick3DNode *object, const ViewBasis &view);
    AngularBounds boundsForCandidate(qreal azimuth, qreal elevation, qreal width, qreal height);
    bool angularBoundsOverlap(const AngularBounds &a, const AngularBounds &b);
    QVector3D angularToWorld(qreal azimuth, qreal elevation, const ViewBasis &view);
    QList<std::pair<qreal, qreal>> generateSpherePoints(qreal angularStep, qreal maxAngle);

    QQuick3DNode *m_viewpoint = nullptr;
    qreal m_distance = 150.0;

    // Additional space around objects in radians
    qreal m_spacing = 0.05;
    QString m_sizePropertyName = QStringLiteral("itemSize");

    // 1 means to test every full width position.
    // 0.5 - every half-width
    qreal m_searchGranularity = 0.5;
    QList<QQuick3DNode *> m_trackedObjects;
};

} // namespace KWin
