/*
    SPDX-FileCopyrightText: 2026 KWin-VR Contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QAbstractListModel>
#include <QJsonArray>
#include <QJsonObject>
#include <QQuaternion>
#include <QTimer>
#include <QVector3D>
#include <QtQmlIntegration>

namespace KWin
{

/**
 * Shape types for work surface primitives.
 */
namespace WorkSurfaceShape
{
Q_NAMESPACE
QML_ELEMENT

enum Type {
    Plane,
    Cube,
    Cylinder,
    Pyramid,
    Sphere,
};
Q_ENUM_NS(Type)
}

/**
 * Layout modes for window arrangement on a work surface face.
 */
namespace WorkSurfaceLayout
{
Q_NAMESPACE
QML_ELEMENT

enum Mode {
    Masonry,
    Grid,
    Stack,
    Freeform,
    Cover,
};
Q_ENUM_NS(Mode)
}

/**
 * Geometric kind of a work surface region. Determines how snapped window
 * textures deform onto the surface (flat, cylindrical arc wrap, spherical
 * patch).
 */
namespace WorkSurfaceRegion
{
Q_NAMESPACE
QML_ELEMENT

enum Kind {
    FlatRect,
    CylinderBody,
    SpherePatch,
};
Q_ENUM_NS(Kind)
}

/**
 * Data for a single face of a work surface.
 */
struct WorkSurfaceFaceData
{
    Q_GADGET
    Q_PROPERTY(int layoutMode MEMBER layoutMode)
    QML_VALUE_TYPE(workSurfaceFaceData)
    QML_STRUCTURED_VALUE
public:
    int layoutMode = WorkSurfaceLayout::Masonry;

    QJsonObject toJson() const;
    static WorkSurfaceFaceData fromJson(const QJsonObject &obj);
};

/**
 * Data for a single work surface instance.
 */
struct WorkSurfaceData
{
    QString id;
    int shapeType = WorkSurfaceShape::Plane;
    QVector3D position;
    QQuaternion rotation;
    QVector3D scale = QVector3D(1, 1, 1);
    QList<WorkSurfaceFaceData> faces;

    QJsonObject toJson() const;
    static WorkSurfaceData fromJson(const QJsonObject &obj);

    static int faceCountForShape(int shapeType);
};

/**
 * Model managing work surface instances with JSON persistence.
 *
 * Surfaces are 3D primitives placed in the VR scene. Each face of a
 * surface can host windows with a configurable layout mode. The model
 * persists to ~/.config/kwinvr-worksurfaces.json.
 */
class WorkSurfaceModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT

public:
    enum Roles {
        SurfaceIdRole = Qt::UserRole + 1,
        ShapeTypeRole,
        PositionRole,
        RotationRole,
        ScaleRole,
        FacesRole,
    };

    explicit WorkSurfaceModel(QObject *parent = nullptr);
    ~WorkSurfaceModel() override;

    QHash<int, QByteArray> roleNames() const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;

    Q_INVOKABLE QString addSurface(int shapeType);
    Q_INVOKABLE void removeSurface(const QString &id);
    Q_INVOKABLE void duplicateSurface(const QString &id);

    Q_INVOKABLE void updateTransform(const QString &id, const QVector3D &position,
                                     const QQuaternion &rotation, const QVector3D &scale);
    Q_INVOKABLE void setFaceLayoutMode(const QString &id, int faceIndex, int layoutMode);

Q_SIGNALS:
    void surfaceAdded(const QString &id);
    void surfaceRemoved(const QString &id);

private:
    void load();
    void scheduleSave();
    void save();

    int indexOfId(const QString &id) const;
    static QString generateId();
    static QString persistPath();

    QList<WorkSurfaceData> m_surfaces;
    QTimer m_saveTimer;
};

} // namespace KWin
