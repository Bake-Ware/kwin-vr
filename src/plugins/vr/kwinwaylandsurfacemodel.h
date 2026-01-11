/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "wayland/subcompositor.h"
#include "wayland/surface.h"

#include <QAbstractListModel>
#include <QQmlEngine>

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
    };

    explicit KwinWaylandSurfaceModel(QObject *parent = nullptr);

    QHash<int, QByteArray> roleNames() const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;

    SurfaceInterface *surface() const;
    void setSurface(SurfaceInterface *newClient);

Q_SIGNALS:
    void surfaceChanged();

private:
    void handleSurfacesChanged();

    QVector<SubSurfaceInterface *> m_subSurfaces;
    SurfaceInterface *m_surface = nullptr;
};

} // namespace KWin
