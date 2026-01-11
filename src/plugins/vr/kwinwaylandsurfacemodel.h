/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef KWINWAYLANDSURFACEMODEL_H
#define KWINWAYLANDSURFACEMODEL_H

#include <QAbstractListModel>
#include <QObject>
#include <QQmlEngine>

#include "wayland/subcompositor.h"
#include "wayland/surface.h"
#include "window.h"

namespace KWin
{
class KwinWaylandSurfaceModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(KWin::SurfaceInterface *surface READ surface WRITE setSurface NOTIFY surfaceChanged FINAL)
    QML_ELEMENT
public:
    enum Roles {
        SurfaceRole = Qt::UserRole + 1,
        SubSurfaceRole = Qt::UserRole + 2,
    };

    explicit KwinWaylandSurfaceModel(QObject *parent = nullptr);

    QHash<int, QByteArray> roleNames() const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;

    KWin::SurfaceInterface *surface() const;
    void setSurface(KWin::SurfaceInterface *newClient);

Q_SIGNALS:
    void surfaceChanged();

private:
    void handleSurfacesChanged();

    QVector<KWin::SubSurfaceInterface *> m_sub_surfaces;
    KWin::SurfaceInterface *m_surface = nullptr;
};

}

#endif // KWINWAYLANDSURFACEMODEL_H
