/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "windowmodelfilter.h"
#include "window.h"
#include "workspace.h"

namespace KWin
{

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
    beginInsertRows(QModelIndex(), m_windows.size(), m_windows.size());
    m_windows.append(window);
    endInsertRows();

    connect(window, &Window::outputChanged, this, &KwinWindowModel::handleWindowChanged);
    connect(window, &Window::transientChanged, this, &KwinWindowModel::handleWindowChanged);
}

void KwinWindowModel::handleWindowChanged()
{
    auto window = qobject_cast<Window *>(sender());
    if (window) {
        markRoleChanged(window, WindowRole);
    }
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
    if (!index.isValid() || index.row() < 0 || index.row() >= m_windows.size()) {
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
    return parent.isValid() ? 0 : m_windows.size();
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
        return false;
    }

    Window *window = qvariant_cast<Window *>(data);
    if (!window) {
        return false;
    }

    if (!window->isClient()) {
        return false;
    }

    switch (window->windowType()) {
    case WindowType::OnScreenDisplay:
    case WindowType::Notification:
    case WindowType::CriticalNotification:
    case WindowType::Dock:
    case WindowType::Tooltip:
    case WindowType::AppletPopup:
        return false;
    default:
        break;
    }

    // Qt maintenance window had isTransient() == true, but transientFor() == nullptr
    if (window->transientFor()) {
        return false;
    }

    return true;
}

KwinWindowModel *PrimaryWindowModelFilter::windowModel() const
{
    return m_windowModel;
}

void PrimaryWindowModelFilter::setWindowModel(KwinWindowModel *newWindowModel)
{
    if (m_windowModel == newWindowModel) {
        return;
    }
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
        return false;
    }

    Window *window = qvariant_cast<Window *>(data);
    return window && window->windowType() == WindowType::OnScreenDisplay;
}

KwinWindowModel *OsdWindowFilter::windowModel() const
{
    return m_windowModel;
}

void OsdWindowFilter::setWindowModel(KwinWindowModel *newWindowModel)
{
    if (m_windowModel == newWindowModel) {
        return;
    }
    m_windowModel = newWindowModel;
    setSourceModel(m_windowModel);
    Q_EMIT windowModelChanged();
}

AbstractTransientWindowModelFilter::AbstractTransientWindowModelFilter(QObject *parent)
    : QSortFilterProxyModel(parent)
{
}

Window *AbstractTransientWindowModelFilter::forTransient() const
{
    return m_forTransient;
}

void AbstractTransientWindowModelFilter::setForTransient(Window *newForTransient)
{
    if (m_forTransient == newForTransient) {
        return;
    }
    if (m_forTransient) {
        disconnect(m_forTransient, &QObject::destroyed, this, &AbstractTransientWindowModelFilter::handleForTransientDestroyed);
    }
    m_forTransient = newForTransient;
    if (m_forTransient) {
        connect(m_forTransient, &QObject::destroyed, this, &AbstractTransientWindowModelFilter::handleForTransientDestroyed);
    }
    Q_EMIT forTransientChanged();
    invalidateFilter();
}

void AbstractTransientWindowModelFilter::handleForTransientDestroyed()
{
    m_forTransient = nullptr;
    Q_EMIT forTransientChanged();
    invalidateFilter();
}

Window *AbstractTransientWindowModelFilter::filterAcceptsRowCommon(int source_row, const QModelIndex &source_parent) const
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
        return nullptr;
    }

    Window *window = qvariant_cast<Window *>(data);
    if (!window) {
        return nullptr;
    }

    if (window == m_forTransient) {
        return nullptr;
    }

    if (window->transientFor() == m_forTransient) {
        return window;
    }

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

void AbstractTransientWindowModelFilter::setWindowModel(KwinWindowModel *newWindowModel)
{
    if (m_windowModel == newWindowModel) {
        return;
    }
    m_windowModel = newWindowModel;
    setSourceModel(m_windowModel);
    Q_EMIT windowModelChanged();
}

HudWindowFilter::HudWindowFilter(QObject *parent)
    : QSortFilterProxyModel{parent}
{
}

bool HudWindowFilter::filterAcceptsRow(int source_row, const QModelIndex &source_parent) const
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
        return false;
    }

    Window *window = qvariant_cast<Window *>(data);
    if (!window || !window->isClient()) {
        return false;
    }

    // Direct type match
    switch (window->windowType()) {
    case WindowType::Notification:
    case WindowType::CriticalNotification:
        return m_showNotifications;
    case WindowType::OnScreenDisplay:
        return m_showOsd;
    case WindowType::Dock:
    case WindowType::Tooltip:
        return m_showDock;
    case WindowType::AppletPopup:
        return m_showAppletPopup;
    default:
        break;
    }

    // Walk the transient chain to find if any ancestor is a HUD window.
    // Handles submenus, flyouts, and tooltips that are children of HUD windows.
    Window *ancestor = window->transientFor();
    for (int depth = 0; ancestor && depth < 10; ++depth) {
        switch (ancestor->windowType()) {
        case WindowType::Dock:
        case WindowType::Tooltip:
            return m_showDock;
        case WindowType::Notification:
        case WindowType::CriticalNotification:
            return m_showNotifications;
        case WindowType::AppletPopup:
            return m_showAppletPopup;
        case WindowType::OnScreenDisplay:
            return m_showOsd;
        default:
            break;
        }
        ancestor = ancestor->transientFor();
    }

    return false;
}

KwinWindowModel *HudWindowFilter::windowModel() const
{
    return m_windowModel;
}

void HudWindowFilter::setWindowModel(KwinWindowModel *newWindowModel)
{
    if (m_windowModel == newWindowModel) {
        return;
    }
    m_windowModel = newWindowModel;
    setSourceModel(m_windowModel);
    Q_EMIT windowModelChanged();
}

bool HudWindowFilter::showNotifications() const
{
    return m_showNotifications;
}

void HudWindowFilter::setShowNotifications(bool show)
{
    if (m_showNotifications == show) {
        return;
    }
    m_showNotifications = show;
    Q_EMIT showNotificationsChanged();
    invalidateFilter();
}

bool HudWindowFilter::showOsd() const
{
    return m_showOsd;
}

void HudWindowFilter::setShowOsd(bool show)
{
    if (m_showOsd == show) {
        return;
    }
    m_showOsd = show;
    Q_EMIT showOsdChanged();
    invalidateFilter();
}

bool HudWindowFilter::showDock() const
{
    return m_showDock;
}

void HudWindowFilter::setShowDock(bool show)
{
    if (m_showDock == show) {
        return;
    }
    m_showDock = show;
    Q_EMIT showDockChanged();
    invalidateFilter();
}

bool HudWindowFilter::showAppletPopup() const
{
    return m_showAppletPopup;
}

void HudWindowFilter::setShowAppletPopup(bool show)
{
    if (m_showAppletPopup == show) {
        return;
    }
    m_showAppletPopup = show;
    Q_EMIT showAppletPopupChanged();
    invalidateFilter();
}

TransientNormalWindowFilter::TransientNormalWindowFilter(QObject *parent)
    : AbstractTransientWindowModelFilter(parent)
{
}

bool TransientNormalWindowFilter::filterAcceptsRow(int source_row, const QModelIndex &source_parent) const
{
    auto window = filterAcceptsRowCommon(source_row, source_parent);
    if (!window) {
        return false;
    }

    return window->windowType() == WindowType::Normal;
}

TransientMenusWindowFilter::TransientMenusWindowFilter(QObject *parent)
    : AbstractTransientWindowModelFilter(parent)
{
}

bool TransientMenusWindowFilter::filterAcceptsRow(int source_row, const QModelIndex &source_parent) const
{
    auto window = filterAcceptsRowCommon(source_row, source_parent);
    if (!window) {
        return false;
    }

    return window->windowType() != WindowType::Normal;
}

} // namespace KWin
