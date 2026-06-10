/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "spaceallocator3d.h"

#include <QMatrix4x4>
#include <QQmlProperty>
#include <QSizeF>
#include <QVariant>
#include <QtMath>
#include <cmath>
#include <limits>

namespace KWin
{

SpaceAllocator3D::SpaceAllocator3D(QObject *parent)
    : QObject(parent)
{
}

QQuick3DNode *SpaceAllocator3D::viewpoint() const
{
    return m_viewpoint;
}

void SpaceAllocator3D::setViewpoint(QQuick3DNode *node)
{
    if (m_viewpoint == node) {
        return;
    }
    if (m_viewpoint) {
        disconnect(m_viewpoint, &QObject::destroyed, this, nullptr);
    }
    m_viewpoint = node;
    if (m_viewpoint) {
        connect(m_viewpoint, &QObject::destroyed, this, [this]() {
            m_viewpoint = nullptr;
            Q_EMIT viewpointChanged();
        });
    }
    Q_EMIT viewpointChanged();
}

qreal SpaceAllocator3D::distance() const
{
    return m_distance;
}

void SpaceAllocator3D::setDistance(qreal d)
{
    if (qFuzzyCompare(m_distance, d)) {
        return;
    }
    m_distance = d;
    Q_EMIT distanceChanged();
}

qreal SpaceAllocator3D::spacing() const
{
    return m_spacing;
}

void SpaceAllocator3D::setSpacing(qreal s)
{
    if (qFuzzyCompare(m_spacing, s)) {
        return;
    }
    m_spacing = s;
    Q_EMIT spacingChanged();
}

QString SpaceAllocator3D::sizePropertyName() const
{
    return m_sizePropertyName;
}

void SpaceAllocator3D::setSizePropertyName(const QString &name)
{
    if (m_sizePropertyName == name) {
        return;
    }
    m_sizePropertyName = name;
    Q_EMIT sizePropertyNameChanged();
}

qreal SpaceAllocator3D::searchGranularity() const
{
    return m_searchGranularity;
}

void SpaceAllocator3D::setSearchGranularity(qreal granularity)
{
    if (qFuzzyCompare(m_searchGranularity, granularity)) {
        return;
    }
    m_searchGranularity = granularity;
    Q_EMIT searchGranularityChanged();
}

void SpaceAllocator3D::registerObject(QQuick3DNode *object)
{
    if (!object || m_trackedObjects.contains(object)) {
        return;
    }
    m_trackedObjects.append(object);
    connect(object, &QObject::destroyed, this, [this, object]() {
        m_trackedObjects.removeAll(object);
    });
}

void SpaceAllocator3D::unregisterObject(QQuick3DNode *object)
{
    if (object) {
        disconnect(object, &QObject::destroyed, this, nullptr);
    }
    m_trackedObjects.removeAll(object);
}

SpaceAllocator3D::ViewBasis SpaceAllocator3D::viewBasis() const
{
    ViewBasis basis;
    if (m_viewpoint) {
        basis.position = m_viewpoint->scenePosition();
        basis.forward = m_viewpoint->forward();
        basis.right = m_viewpoint->right();
        basis.up = m_viewpoint->up();
    } else {
        basis.position = QVector3D(0, 0, 0);
        basis.forward = QVector3D(0, 0, -1);
        basis.right = QVector3D(1, 0, 0);
        basis.up = QVector3D(0, 1, 0);
    }
    return basis;
}

AngularBounds SpaceAllocator3D::projectToAngular(QQuick3DNode *object, const ViewBasis &view)
{
    const QMatrix4x4 transform = object->sceneTransform();

    const QSizeF size = QQmlProperty::read(object, m_sizePropertyName).toSizeF();
    const qreal w = size.width();
    const qreal h = size.height();

    // Local corners of the rectangle (centered at origin)
    const float hw = static_cast<float>(w / 2);
    const float hh = static_cast<float>(h / 2);
    const QVector3D localCorners[4] = {
        {-hw, -hh, 0},
        {+hw, -hh, 0},
        {+hw, +hh, 0},
        {-hw, +hh, 0}};

    qreal minAz = std::numeric_limits<qreal>::infinity();
    qreal maxAz = -std::numeric_limits<qreal>::infinity();
    qreal minEl = std::numeric_limits<qreal>::infinity();
    qreal maxEl = -std::numeric_limits<qreal>::infinity();

    for (int i = 0; i < 4; ++i) {
        const QVector3D worldCorner = transform.map(localCorners[i]);
        const QVector3D toCorner = (worldCorner - view.position).normalized();

        // Project onto view basis to get angles relative to camera direction
        const qreal dotForward = QVector3D::dotProduct(toCorner, view.forward);
        const qreal dotRight = QVector3D::dotProduct(toCorner, view.right);
        const qreal dotUp = QVector3D::dotProduct(toCorner, view.up);

        // Azimuth: angle from forward in the horizontal plane (right is positive)
        const qreal azimuth = std::atan2(dotRight, dotForward);
        // Elevation: angle from forward in the vertical plane (up is positive)
        const qreal elevation = std::asin(std::clamp(dotUp, -1.0, 1.0));

        minAz = qMin(minAz, azimuth);
        maxAz = qMax(maxAz, azimuth);
        minEl = qMin(minEl, elevation);
        maxEl = qMax(maxEl, elevation);
    }

    return {minAz, maxAz, minEl, maxEl};
}

AngularBounds SpaceAllocator3D::boundsForCandidate(qreal azimuth, qreal elevation, qreal width, qreal height)
{
    // The radius of the horizontal circle at this elevation is reduced by cos(elevation).
    // Clamp cos(elevation) to avoid division by zero.
    const qreal cosEl = std::max(0.01, std::cos(elevation));

    // Convert world-space dimensions to angular size, then add angular spacing
    const qreal halfW = std::atan(width / 2.0 / (m_distance * cosEl)) + m_spacing / 2.0;
    const qreal halfH = std::atan(height / 2.0 / m_distance) + m_spacing / 2.0;
    return {azimuth - halfW, azimuth + halfW, elevation - halfH, elevation + halfH};
}

bool SpaceAllocator3D::angularBoundsOverlap(const AngularBounds &a, const AngularBounds &b)
{
    if (a.maxAzimuth < b.minAzimuth || b.maxAzimuth < a.minAzimuth) {
        return false;
    }
    if (a.maxElevation < b.minElevation || b.maxElevation < a.minElevation) {
        return false;
    }
    return true;
}

QVector3D SpaceAllocator3D::angularToWorld(qreal azimuth, qreal elevation, const ViewBasis &view)
{
    // Convert angles back to direction in view space, then to world space
    // forward = cos(el) * cos(az), right = cos(el) * sin(az), up = sin(el)
    const qreal cosEl = std::cos(elevation);
    const qreal sinEl = std::sin(elevation);
    const qreal cosAz = std::cos(azimuth);
    const qreal sinAz = std::sin(azimuth);

    // Direction in view space: forward * cos(el)*cos(az) + right * cos(el)*sin(az) + up * sin(el)
    const QVector3D direction = view.forward * (cosEl * cosAz)
        + view.right * (cosEl * sinAz)
        + view.up * sinEl;

    return view.position + direction.normalized() * m_distance;
}

QList<std::pair<qreal, qreal>> SpaceAllocator3D::generateSpherePoints(qreal angularStep, qreal maxAngle)
{
    QList<std::pair<qreal, qreal>> positions;

    // Center position: just directly forward.
    positions.append({0.0, 0.0});

    // Generate points in concentric rings expanding from center
    // Each ring is at a fixed angular distance (alpha) from forward direction
    for (qreal alpha = angularStep; alpha <= maxAngle; alpha += angularStep) {
        // Number of points around this ring - proportional to circumference
        const qreal circumference = 2.0 * M_PI * std::sin(alpha);
        const int numPoints = std::max(4, static_cast<int>(std::ceil(circumference / angularStep)));

        for (int i = 0; i < numPoints; ++i) {
            // Angle around the forward axis (0 to 2*PI)
            const qreal theta = 2.0 * M_PI * i / numPoints;

            // Convert (alpha, theta) to (azimuth, elevation) using spherical geometry
            // A point at angle alpha from forward, rotated by theta around forward axis:
            // 1. forward component = cos(alpha)
            // 2. right component = sin(alpha) * sin(theta)
            // 3. up component = sin(alpha) * cos(theta)
            const qreal sinAlpha = std::sin(alpha);
            const qreal cosAlpha = std::cos(alpha);
            const qreal forwardComponent = cosAlpha;
            const qreal rightComponent = sinAlpha * std::sin(theta);
            const qreal upComponent = sinAlpha * std::cos(theta);

            // Convert to azimuth/elevation
            const qreal azimuth = std::atan2(rightComponent, forwardComponent);
            const qreal elevation = std::asin(std::clamp(upComponent, -1.0, 1.0));

            positions.append({azimuth, elevation});
        }
    }

    return positions;
}

QVector3D SpaceAllocator3D::findFreePosition(qreal width, qreal height)
{
    const ViewBasis view = viewBasis();

    // Pre-calculate angular bounds for all tracked objects
    QList<AngularBounds> existingBounds;
    existingBounds.reserve(m_trackedObjects.size());
    for (auto *obj : std::as_const(m_trackedObjects)) {
        existingBounds.append(projectToAngular(obj, view));
    }

    // Angular step based on object size and search granularity
    const qreal angularStep = (std::atan(width / m_distance) + m_spacing) * m_searchGranularity;

    // Generate candidate positions (sorted by distance from center), capped at
    // 90° from forward — new spawns stay in the front hemisphere where the user
    // can at least see them peripherally, instead of landing behind the head as
    // the front fills up. Overflow goes to the VOC-PLACE-030 fallback instead.
    const auto candidates = generateSpherePoints(angularStep, M_PI_2);

    // Check each candidate position
    for (const auto &[az, el] : candidates) {
        const AngularBounds candidate = boundsForCandidate(az, el, width, height);

        bool occluded = false;
        for (const auto &existing : existingBounds) {
            if (angularBoundsOverlap(candidate, existing)) {
                occluded = true;
                break;
            }
        }

        if (!occluded) {
            return angularToWorld(az, el, view);
        }
    }

    // Fallback... what would be better to do here?
    return view.position + view.forward * m_distance;
}

QVariantList SpaceAllocator3D::debugGetSpherePoints(qreal angularStep, qreal maxAngle)
{
    const ViewBasis view = viewBasis();
    const auto points = generateSpherePoints(angularStep, maxAngle);

    QVariantList result;
    result.reserve(points.size());

    for (const auto &[az, el] : points) {
        result.append(QVariant::fromValue(angularToWorld(az, el, view)));
    }

    return result;
}

} // namespace KWin
