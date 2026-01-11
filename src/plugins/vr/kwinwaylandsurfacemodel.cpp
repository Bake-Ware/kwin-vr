/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinwaylandsurfacemodel.h"
#include "kwinvr_logging.h"
#include "wayland/subcompositor.h"
using namespace KWin;
KwinWaylandSurfaceModel::KwinWaylandSurfaceModel(QObject *parent)
    : QAbstractListModel{parent}
{
}

QHash<int, QByteArray> KwinWaylandSurfaceModel::roleNames() const
{
    return {
        {Qt::DisplayRole, QByteArrayLiteral("surface")},
        {SurfaceRole, QByteArrayLiteral("surface")},
        {SubSurfaceRole, QByteArrayLiteral("subsurface")},
    };
}

QVariant KwinWaylandSurfaceModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_sub_surfaces.count()) {
        return QVariant();
    }

    SubSurfaceInterface *ss = m_sub_surfaces[index.row()];
    switch (role) {
    case Qt::DisplayRole:
    case SurfaceRole:
        return QVariant::fromValue(ss->surface());
    case SubSurfaceRole:
        return QVariant::fromValue(ss);
    default:
        return QVariant();
    }
}

int KwinWaylandSurfaceModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_sub_surfaces.count();
}

void KwinWaylandSurfaceModel::handleSurfacesChanged()
{
    QVector<SubSurfaceInterface *> newSubSurfaces = m_surface->below() + m_surface->above();

    for (int i = m_sub_surfaces.size() - 1; i >= 0; --i) {
        if (!newSubSurfaces.contains(m_sub_surfaces[i])) {
            beginRemoveRows(QModelIndex(), i, i);
            m_sub_surfaces.removeAt(i);
            endRemoveRows();
        }
    }

    for (int newIndex = 0; newIndex < newSubSurfaces.size(); ++newIndex) {
        SubSurfaceInterface *surface = newSubSurfaces[newIndex];
        int oldIndex = m_sub_surfaces.indexOf(surface);

        if (oldIndex == -1) {
            beginInsertRows(QModelIndex(), newIndex, newIndex);
            m_sub_surfaces.insert(newIndex, surface);
            endInsertRows();
        } else if (oldIndex != newIndex) {
            auto targetIndex = newIndex > oldIndex ? newIndex + 1 : newIndex;
            if (beginMoveRows(QModelIndex(), oldIndex, oldIndex, QModelIndex(), targetIndex)) {
                m_sub_surfaces.move(oldIndex, newIndex);
                endMoveRows();
            } else {
                qCCritical(KWINVR) << "Failed to move element";
            }
        }
    }
}

SurfaceInterface *KwinWaylandSurfaceModel::surface() const
{
    return m_surface;
}

void KwinWaylandSurfaceModel::setSurface(KWin::SurfaceInterface *newClient)
{
    if (m_surface == newClient)
        return;
    if (m_surface) {
        disconnect(m_surface, &SurfaceInterface::childSubSurfacesChanged, this, &KwinWaylandSurfaceModel::handleSurfacesChanged);
    }

    m_surface = newClient;

    if (m_surface) {
        connect(m_surface, &SurfaceInterface::childSubSurfacesChanged, this, &KwinWaylandSurfaceModel::handleSurfacesChanged);
        beginResetModel();
        m_sub_surfaces = m_surface->below() + m_surface->above();
        endResetModel();
    } else {
        beginResetModel();
        m_sub_surfaces.clear();
        endResetModel();
    }
    Q_EMIT surfaceChanged();
}
