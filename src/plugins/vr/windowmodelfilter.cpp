/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "windowmodelfilter.h"
#include "window.h"
#include "workspace.h"

using namespace KWin;

KwinWindowModel::KwinWindowModel(QObject *parent)
    : QAbstractListModel(parent)
{
    connect(workspace(), &Workspace::windowAdded, this, &KwinWindowModel::handleWindowAdded);
    connect(workspace(), &Workspace::windowRemoved, this, &KwinWindowModel::handleWindowRemoved);
    m_windows = workspace()->windows();
}

void KwinWindowModel::markRoleChanged(Window *window, int role)
{
    const QModelIndex row = index(m_windows.indexOf(window), 0);
    Q_EMIT dataChanged(row, row, {role});
}

void KwinWindowModel::handleWindowAdded(Window *window)
{
    beginInsertRows(QModelIndex(), m_windows.count(), m_windows.count());
    m_windows.append(window);
    endInsertRows();
}

void KwinWindowModel::handleWindowRemoved(Window *window)
{
    const int index = m_windows.indexOf(window);
    Q_ASSERT(index != -1);

    beginRemoveRows(QModelIndex(), index, index);
    m_windows.removeAt(index);
    endRemoveRows();
}

QHash<int, QByteArray> KwinWindowModel::roleNames() const
{
    return {
        {Qt::DisplayRole, QByteArrayLiteral("display")},
        {WindowRole, QByteArrayLiteral("window")},
    };
}

QVariant KwinWindowModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_windows.count()) {
        return QVariant();
    }

    Window *window = m_windows[index.row()];
    switch (role) {
    case Qt::DisplayRole:
    case WindowRole:
        return QVariant::fromValue(window);
    default:
        return QVariant();
    }
}

int KwinWindowModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_windows.count();
}

PrimaryWindowModelFilter::PrimaryWindowModelFilter(QObject *parent)
    : QSortFilterProxyModel{parent}
{
}

bool PrimaryWindowModelFilter::filterAcceptsRow(int source_row, const QModelIndex &source_parent) const
{
    if (!m_windowModel) {
        return false;
    }

    const QModelIndex index = m_windowModel->index(source_row, 0, source_parent);
    if (!index.isValid()) {
        return false;
    }

    const QVariant data = index.data();
    if (!data.isValid()) {
        return true;
    }

    Window *window = qvariant_cast<Window *>(data);
    if (!window) {
        return false;
    }

    if (m_output && m_output != window->output())
        return false;

    if (!window->isClient())
        return false;

    if (window->windowType() == WindowType::OnScreenDisplay)
        return false;

    // Exclude the VR compositor window to prevent recursive rendering
    if (window->resourceClass() == QLatin1String("openxr"))
        return false;

    // Qt maintenance window had isTransient() == true, but transientFor() == nullptr
    // if(window->isTransient())
    if (window->transientFor())
        return false;

    return true;
}

KwinWindowModel *PrimaryWindowModelFilter::windowModel() const
{
    return m_windowModel;
}

void PrimaryWindowModelFilter::setWindowModel(KWin::KwinWindowModel *newWindowModel)
{
    if (m_windowModel == newWindowModel)
        return;
    m_windowModel = newWindowModel;
    setSourceModel(m_windowModel);
    Q_EMIT windowModelChanged();
}

LogicalOutput *PrimaryWindowModelFilter::output() const
{
    return m_output;
}

void PrimaryWindowModelFilter::setOutput(KWin::LogicalOutput *newOutput)
{
    if (m_output == newOutput)
        return;
    m_output = newOutput;
    Q_EMIT outputChanged();
    invalidateFilter();
}

TransientWindowModelFilter::TransientWindowModelFilter(QObject *parent)
    : QSortFilterProxyModel{parent}
{
}

KWin::Window *TransientWindowModelFilter::forTransient() const
{
    return m_forTransient;
}

void TransientWindowModelFilter::setForTransient(KWin::Window *newForTransient)
{
    if (m_forTransient == newForTransient)
        return;
    m_forTransient = newForTransient;
    Q_EMIT forTransientChanged();
    invalidateFilter();
}

bool TransientWindowModelFilter::filterAcceptsRow(int source_row, const QModelIndex &source_parent) const
{
    if (!m_windowModel || !m_forTransient) {
        return false;
    }

    const QModelIndex index = m_windowModel->index(source_row, 0, source_parent);
    if (!index.isValid()) {
        return false;
    }

    const QVariant data = index.data();
    if (!data.isValid()) {
        return true;
    }

    Window *window = qvariant_cast<Window *>(data);
    if (!window) {
        return false;
    }

    if (window == m_forTransient)
        return false;

    if (window->transientFor() == m_forTransient)
        return true;

    if (!window->isClient()) {
        if (Window::belongToSameApplication(window, m_forTransient)) {
            return true;
        }
    }

    return false;
}

KwinWindowModel *TransientWindowModelFilter::windowModel() const
{
    return m_windowModel;
}

void TransientWindowModelFilter::setWindowModel(KWin::KwinWindowModel *newWindowModel)
{
    if (m_windowModel == newWindowModel)
        return;
    m_windowModel = newWindowModel;
    setSourceModel(m_windowModel);
    Q_EMIT windowModelChanged();
}

OsdWindowFilter::OsdWindowFilter(QObject *parent)
    : QSortFilterProxyModel{parent}
{
}

bool OsdWindowFilter::filterAcceptsRow(int source_row, const QModelIndex &source_parent) const
{
    if (!m_windowModel) {
        return false;
    }

    const QModelIndex index = m_windowModel->index(source_row, 0, source_parent);
    if (!index.isValid()) {
        return false;
    }

    const QVariant data = index.data();
    if (!data.isValid()) {
        return true;
    }

    Window *window = qvariant_cast<Window *>(data);
    return window && window->windowType() == WindowType::OnScreenDisplay;
}

KwinWindowModel *OsdWindowFilter::windowModel() const
{
    return m_windowModel;
}

void OsdWindowFilter::setWindowModel(KWin::KwinWindowModel *newWindowModel)
{
    if (m_windowModel == newWindowModel)
        return;
    m_windowModel = newWindowModel;
    setSourceModel(m_windowModel);
    Q_EMIT windowModelChanged();
}

AbstractTransientWindowModelFilter::AbstractTransientWindowModelFilter(QObject *parent)
    : QSortFilterProxyModel(parent)
{
}

KWin::Window *AbstractTransientWindowModelFilter::forTransient() const
{
    return m_forTransient;
}

void AbstractTransientWindowModelFilter::setForTransient(KWin::Window *newForTransient)
{
    if (m_forTransient == newForTransient)
        return;
    m_forTransient = newForTransient;
    Q_EMIT forTransientChanged();
    invalidateFilter();
}

KWin::Window *AbstractTransientWindowModelFilter::filterAcceptsRowCommon(int source_row, const QModelIndex &source_parent) const
{
    if (!m_windowModel || !m_forTransient) {
        return nullptr;
    }

    const QModelIndex index = m_windowModel->index(source_row, 0, source_parent);
    if (!index.isValid()) {
        return nullptr;
    }

    const QVariant data = index.data();
    if (!data.isValid()) {
        return nullptr; //?
    }

    Window *window = qvariant_cast<Window *>(data);
    if (!window) {
        return nullptr;
    }

    if (window == m_forTransient)
        return nullptr;

    if (window->transientFor() == m_forTransient)
        return window;

    if (!window->isClient()) {
        if (Window::belongToSameApplication(window, m_forTransient)) {
            return window;
        }
    }

    return nullptr;
}

KwinWindowModel *AbstractTransientWindowModelFilter::windowModel() const
{
    return m_windowModel;
}

void AbstractTransientWindowModelFilter::setWindowModel(KWin::KwinWindowModel *newWindowModel)
{
    if (m_windowModel == newWindowModel)
        return;
    m_windowModel = newWindowModel;
    setSourceModel(m_windowModel);
    Q_EMIT windowModelChanged();
}

TransientNormalWindowFilter::TransientNormalWindowFilter(QObject *parent)
    : AbstractTransientWindowModelFilter(parent)
{
}
bool TransientNormalWindowFilter::filterAcceptsRow(int source_row, const QModelIndex &source_parent) const
{
    auto win = filterAcceptsRowCommon(source_row, source_parent);
    if (!win)
        return false;

    return win->windowType() == WindowType::Normal;
}

TransientMenusWindowFilter::TransientMenusWindowFilter(QObject *parent)
    : AbstractTransientWindowModelFilter(parent)
{
}
bool TransientMenusWindowFilter::filterAcceptsRow(int source_row, const QModelIndex &source_parent) const
{
    auto win = filterAcceptsRowCommon(source_row, source_parent);
    if (!win)
        return false;

    return win->windowType() != WindowType::Normal;
}
