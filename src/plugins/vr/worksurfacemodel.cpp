/*
    SPDX-FileCopyrightText: 2026 KWin-VR Contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "worksurfacemodel.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QStandardPaths>
#include <QUuid>

// Temporary debug log that bypasses journald rate limiting
static void wsLog(const QString &msg)
{
    QFile f(QStringLiteral("/tmp/kwinvr-worksurface.log"));
    if (f.open(QIODevice::Append | QIODevice::Text)) {
        f.write(QDateTime::currentDateTime().toString(Qt::ISODateWithMs).toUtf8());
        f.write(" ");
        f.write(msg.toUtf8());
        f.write("\n");
    }
}

namespace KWin
{

// -- WorkSurfaceFaceData ----------------------------------------------------

QJsonObject WorkSurfaceFaceData::toJson() const
{
    return {
        {QStringLiteral("layoutMode"), layoutMode},
    };
}

WorkSurfaceFaceData WorkSurfaceFaceData::fromJson(const QJsonObject &obj)
{
    WorkSurfaceFaceData d;
    d.layoutMode = obj.value(QStringLiteral("layoutMode")).toInt(WorkSurfaceLayout::Masonry);
    return d;
}

// -- WorkSurfaceData --------------------------------------------------------

static QJsonObject vec3ToJson(const QVector3D &v)
{
    return {
        {QStringLiteral("x"), v.x()},
        {QStringLiteral("y"), v.y()},
        {QStringLiteral("z"), v.z()},
    };
}

static QVector3D vec3FromJson(const QJsonObject &obj, const QVector3D &fallback = {})
{
    if (obj.isEmpty()) {
        return fallback;
    }
    return QVector3D(
        obj.value(QStringLiteral("x")).toDouble(fallback.x()),
        obj.value(QStringLiteral("y")).toDouble(fallback.y()),
        obj.value(QStringLiteral("z")).toDouble(fallback.z()));
}

static QJsonObject quatToJson(const QQuaternion &q)
{
    return {
        {QStringLiteral("w"), q.scalar()},
        {QStringLiteral("x"), q.x()},
        {QStringLiteral("y"), q.y()},
        {QStringLiteral("z"), q.z()},
    };
}

static QQuaternion quatFromJson(const QJsonObject &obj)
{
    if (obj.isEmpty()) {
        return QQuaternion();
    }
    return QQuaternion(
        obj.value(QStringLiteral("w")).toDouble(1),
        obj.value(QStringLiteral("x")).toDouble(0),
        obj.value(QStringLiteral("y")).toDouble(0),
        obj.value(QStringLiteral("z")).toDouble(0));
}

int WorkSurfaceData::faceCountForShape(int shapeType)
{
    switch (shapeType) {
    case WorkSurfaceShape::Plane:
        return 1;
    case WorkSurfaceShape::Cube:
        return 6;
    case WorkSurfaceShape::Cylinder:
        return 3; // body + 2 caps
    case WorkSurfaceShape::Pyramid:
        return 5; // 4 sides + base
    case WorkSurfaceShape::Sphere:
        return 1; // single forward-facing spherical patch
    default:
        return 1;
    }
}

QJsonObject WorkSurfaceData::toJson() const
{
    QJsonArray facesArray;
    for (const auto &face : faces) {
        facesArray.append(face.toJson());
    }

    return {
        {QStringLiteral("id"), id},
        {QStringLiteral("shapeType"), shapeType},
        {QStringLiteral("position"), vec3ToJson(position)},
        {QStringLiteral("rotation"), quatToJson(rotation)},
        {QStringLiteral("scale"), vec3ToJson(scale)},
        {QStringLiteral("faces"), facesArray},
    };
}

WorkSurfaceData WorkSurfaceData::fromJson(const QJsonObject &obj)
{
    WorkSurfaceData d;
    d.id = obj.value(QStringLiteral("id")).toString();
    d.shapeType = obj.value(QStringLiteral("shapeType")).toInt(WorkSurfaceShape::Plane);
    d.position = vec3FromJson(obj.value(QStringLiteral("position")).toObject());
    d.rotation = quatFromJson(obj.value(QStringLiteral("rotation")).toObject());
    d.scale = vec3FromJson(obj.value(QStringLiteral("scale")).toObject(), QVector3D(1, 1, 1));

    const auto facesArray = obj.value(QStringLiteral("faces")).toArray();
    for (const auto &faceVal : facesArray) {
        d.faces.append(WorkSurfaceFaceData::fromJson(faceVal.toObject()));
    }

    // Ensure we have the right number of faces
    const int expected = faceCountForShape(d.shapeType);
    while (d.faces.size() < expected) {
        d.faces.append(WorkSurfaceFaceData());
    }
    while (d.faces.size() > expected) {
        d.faces.removeLast();
    }

    return d;
}

// -- WorkSurfaceModel -------------------------------------------------------

WorkSurfaceModel::WorkSurfaceModel(QObject *parent)
    : QAbstractListModel(parent)
{
    wsLog(QStringLiteral("WorkSurfaceModel constructed"));
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(500);
    connect(&m_saveTimer, &QTimer::timeout, this, &WorkSurfaceModel::save);
    load();
}

WorkSurfaceModel::~WorkSurfaceModel()
{
    if (m_saveTimer.isActive()) {
        save();
    }
}

QHash<int, QByteArray> WorkSurfaceModel::roleNames() const
{
    return {
        {SurfaceIdRole, QByteArrayLiteral("surfaceId")},
        {ShapeTypeRole, QByteArrayLiteral("shapeType")},
        {PositionRole, QByteArrayLiteral("surfacePosition")},
        {RotationRole, QByteArrayLiteral("surfaceRotation")},
        {ScaleRole, QByteArrayLiteral("surfaceScale")},
        {FacesRole, QByteArrayLiteral("surfaceFaces")},
    };
}

QVariant WorkSurfaceModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_surfaces.size()) {
        return QVariant();
    }

    // Log first data() call per surface to confirm delegate creation
    if (role == SurfaceIdRole) {
        wsLog(QStringLiteral("data() queried for row=%1, role=SurfaceIdRole, id=%2")
                  .arg(index.row())
                  .arg(m_surfaces[index.row()].id));
    }

    const auto &s = m_surfaces[index.row()];
    switch (role) {
    case SurfaceIdRole:
        return s.id;
    case ShapeTypeRole:
        return s.shapeType;
    case PositionRole:
        return s.position;
    case RotationRole:
        return s.rotation;
    case ScaleRole:
        return s.scale;
    case FacesRole: {
        QVariantList list;
        for (const auto &f : s.faces) {
            list.append(QVariant::fromValue(f));
        }
        return list;
    }
    default:
        return QVariant();
    }
}

int WorkSurfaceModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_surfaces.size();
}

QString WorkSurfaceModel::addSurface(int shapeType)
{
    wsLog(QStringLiteral("addSurface called with shapeType=%1, current count=%2")
              .arg(shapeType)
              .arg(m_surfaces.size()));

    WorkSurfaceData surface;
    surface.id = generateId();
    wsLog(QStringLiteral("addSurface: new id=%1, faceCount=%2")
              .arg(surface.id)
              .arg(WorkSurfaceData::faceCountForShape(shapeType)));
    surface.shapeType = shapeType;
    surface.scale = QVector3D(1, 1, 1);

    const int faceCount = WorkSurfaceData::faceCountForShape(shapeType);
    for (int i = 0; i < faceCount; ++i) {
        surface.faces.append(WorkSurfaceFaceData());
    }

    wsLog(QStringLiteral("addSurface: beginInsertRows at %1").arg(m_surfaces.size()));
    beginInsertRows(QModelIndex(), m_surfaces.size(), m_surfaces.size());
    m_surfaces.append(surface);
    endInsertRows();
    wsLog(QStringLiteral("addSurface: endInsertRows done, rowCount=%1").arg(m_surfaces.size()));

    scheduleSave();
    Q_EMIT surfaceAdded(surface.id);
    wsLog(QStringLiteral("addSurface: returning id=%1").arg(surface.id));
    return surface.id;
}

void WorkSurfaceModel::removeSurface(const QString &id)
{
    const int idx = indexOfId(id);
    if (idx < 0) {
        return;
    }

    beginRemoveRows(QModelIndex(), idx, idx);
    m_surfaces.removeAt(idx);
    endRemoveRows();

    scheduleSave();
    Q_EMIT surfaceRemoved(id);
}

void WorkSurfaceModel::duplicateSurface(const QString &id)
{
    const int idx = indexOfId(id);
    if (idx < 0) {
        return;
    }

    WorkSurfaceData copy = m_surfaces[idx];
    copy.id = generateId();
    // Offset the copy slightly so it's visible
    copy.position += QVector3D(10, 0, 0);

    beginInsertRows(QModelIndex(), m_surfaces.size(), m_surfaces.size());
    m_surfaces.append(copy);
    endInsertRows();

    scheduleSave();
    Q_EMIT surfaceAdded(copy.id);
}

void WorkSurfaceModel::updateTransform(const QString &id, const QVector3D &position,
                                       const QQuaternion &rotation, const QVector3D &scale)
{
    wsLog(QStringLiteral("updateTransform id=%1 pos=(%2,%3,%4)")
              .arg(id)
              .arg(position.x())
              .arg(position.y())
              .arg(position.z()));

    const int idx = indexOfId(id);
    if (idx < 0) {
        wsLog(QStringLiteral("updateTransform: id not found!"));
        return;
    }

    auto &s = m_surfaces[idx];
    s.position = position;
    s.rotation = rotation;
    s.scale = scale;

    const auto mi = index(idx);
    Q_EMIT dataChanged(mi, mi, {PositionRole, RotationRole, ScaleRole});
    scheduleSave();
}

void WorkSurfaceModel::setFaceLayoutMode(const QString &id, int faceIndex, int layoutMode)
{
    const int idx = indexOfId(id);
    if (idx < 0) {
        return;
    }

    auto &s = m_surfaces[idx];
    if (faceIndex < 0 || faceIndex >= s.faces.size()) {
        return;
    }

    s.faces[faceIndex].layoutMode = layoutMode;

    const auto mi = index(idx);
    Q_EMIT dataChanged(mi, mi, {FacesRole});
    scheduleSave();
}

// -- Persistence ------------------------------------------------------------

QString WorkSurfaceModel::persistPath()
{
    const QString configDir = QStandardPaths::writableLocation(QStandardPaths::ConfigLocation);
    return configDir + QStringLiteral("/kwinvr-worksurfaces.json");
}

void WorkSurfaceModel::load()
{
    QFile file(persistPath());
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }

    const auto doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isObject()) {
        return;
    }

    const auto root = doc.object();
    const auto surfaces = root.value(QStringLiteral("surfaces")).toArray();

    beginResetModel();
    m_surfaces.clear();
    for (const auto &val : surfaces) {
        m_surfaces.append(WorkSurfaceData::fromJson(val.toObject()));
    }
    endResetModel();
}

void WorkSurfaceModel::scheduleSave()
{
    m_saveTimer.start();
}

void WorkSurfaceModel::save()
{
    QJsonArray surfacesArray;
    for (const auto &s : m_surfaces) {
        surfacesArray.append(s.toJson());
    }

    QJsonObject root;
    root[QStringLiteral("version")] = 1;
    root[QStringLiteral("surfaces")] = surfacesArray;

    const QString path = persistPath();
    QDir().mkpath(QFileInfo(path).absolutePath());

    QFile file(path);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    }
}

int WorkSurfaceModel::indexOfId(const QString &id) const
{
    for (int i = 0; i < m_surfaces.size(); ++i) {
        if (m_surfaces[i].id == id) {
            return i;
        }
    }
    return -1;
}

QString WorkSurfaceModel::generateId()
{
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

} // namespace KWin
