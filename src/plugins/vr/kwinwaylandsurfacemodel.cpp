/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinwaylandsurfacemodel.h"
#include "kwinvr_logging.h"

namespace KWin
{

KwinWaylandSurfaceModel::KwinWaylandSurfaceModel(QObject *parent)
    : QAbstractListModel{parent}
{
}

QHash<int, QByteArray> KwinWaylandSurfaceModel::roleNames() const
{
    return {
        {Qt::DisplayRole, QByteArrayLiteral("surface")},
        {SurfaceRole, QByteArrayLiteral("surface")},
    };
}

QVariant KwinWaylandSurfaceModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_subSurfaces.size()) {
        return QVariant();
    }

    auto subSurface = m_subSurfaces[index.row()];
    switch (role) {
    case Qt::DisplayRole:
    case SurfaceRole:
        return QVariant::fromValue(subSurface->surface());
    default:
        return QVariant();
    }
}

int KwinWaylandSurfaceModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_subSurfaces.size();
}

void KwinWaylandSurfaceModel::handleSurfacesChanged()
{
    QVector<SubSurfaceInterface *> newSubSurfaces = m_surface->below() + m_surface->above();

    for (int i = m_subSurfaces.size() - 1; i >= 0; --i) {
        if (!newSubSurfaces.contains(m_subSurfaces[i])) {
            beginRemoveRows(QModelIndex(), i, i);
            m_subSurfaces.removeAt(i);
            endRemoveRows();
        }
    }

    for (int newIndex = 0; newIndex < newSubSurfaces.size(); ++newIndex) {
        SubSurfaceInterface *surface = newSubSurfaces[newIndex];
        int oldIndex = m_subSurfaces.indexOf(surface);

        if (oldIndex == -1) {
            beginInsertRows(QModelIndex(), newIndex, newIndex);
            m_subSurfaces.insert(newIndex, surface);
            endInsertRows();
        } else if (oldIndex != newIndex) {
            auto targetIndex = newIndex > oldIndex ? newIndex + 1 : newIndex;
            if (beginMoveRows(QModelIndex(), oldIndex, oldIndex, QModelIndex(), targetIndex)) {
                m_subSurfaces.move(oldIndex, newIndex);
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

void KwinWaylandSurfaceModel::setSurface(SurfaceInterface *newClient)
{
    if (m_surface == newClient) {
        return;
    }
    if (m_surface) {
        disconnect(m_surface, &SurfaceInterface::childSubSurfacesChanged, this, &KwinWaylandSurfaceModel::handleSurfacesChanged);
    }

    m_surface = newClient;

    if (m_surface) {
        connect(m_surface, &SurfaceInterface::childSubSurfacesChanged, this, &KwinWaylandSurfaceModel::handleSurfacesChanged);
        beginResetModel();
        m_subSurfaces = m_surface->below() + m_surface->above();
        endResetModel();
    } else {
        beginResetModel();
        m_subSurfaces.clear();
        endResetModel();
    }
    Q_EMIT surfaceChanged();
}

} // namespace KWin
