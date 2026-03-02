/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "outputmodel.h"
#include "core/output.h"
#include "workspace.h"

using namespace KWin;
OutputModel::OutputModel(QObject *parent)
    : QAbstractListModel{parent}
{
    connect(workspace(), &Workspace::outputAdded, this, &OutputModel::handleOutputAdded);
    connect(workspace(), &Workspace::outputRemoved, this, &OutputModel::handleOutputRemoved);

    // Auto-exclude outputs forced as desktop (they are headset outputs, not content screens)
    const QString forceDesktop = qEnvironmentVariable("KWIN_FORCE_DESKTOP_OUTPUTS");
    if (!forceDesktop.isEmpty()) {
        m_excludeOutputs = forceDesktop.split(QLatin1Char(','), Qt::SkipEmptyParts);
    }

    m_allOutputs = workspace()->outputs();
    rebuildFilteredList();
}

QHash<int, QByteArray> OutputModel::roleNames() const
{
    return {
        {Qt::DisplayRole, QByteArrayLiteral("display")},
        {OutputRole, QByteArrayLiteral("output")},
    };
}

QVariant OutputModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_outputs.count()) {
        return QVariant();
    }

    LogicalOutput *output = m_outputs[index.row()];
    switch (role) {
    case Qt::DisplayRole:
    case OutputRole:
        return QVariant::fromValue(output);
    default:
        return QVariant();
    }
}

int OutputModel::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : m_outputs.count();
}

bool OutputModel::shouldExclude(LogicalOutput *output) const
{
    auto *bo = kwinGetBackendOutput(output);
    const QString name = bo->name();
    // Exclude headset outputs (from KWIN_FORCE_DESKTOP_OUTPUTS, e.g. DP-1 in SBS mode)
    if (!m_excludeOutputs.isEmpty() && m_excludeOutputs.contains(name))
        return true;
    // Exclude virtual outputs (created by KwinVirtualScreenHandle as VR rendering targets)
    if (name.startsWith(QLatin1String("Virtual")))
        return true;
    return false;
}

void OutputModel::rebuildFilteredList()
{
    beginResetModel();
    m_outputs.clear();
    for (auto *output : m_allOutputs) {
        if (!shouldExclude(output)) {
            m_outputs.append(output);
        }
    }
    endResetModel();
}

void OutputModel::handleOutputAdded(LogicalOutput *output)
{
    m_allOutputs.append(output);
    if (!shouldExclude(output)) {
        beginInsertRows(QModelIndex(), m_outputs.count(), m_outputs.count());
        m_outputs.append(output);
        endInsertRows();
    }
}

void OutputModel::handleOutputRemoved(LogicalOutput *output)
{
    m_allOutputs.removeOne(output);
    const int index = m_outputs.indexOf(output);
    if (index != -1) {
        beginRemoveRows(QModelIndex(), index, index);
        m_outputs.removeAt(index);
        endRemoveRows();
    }
}
