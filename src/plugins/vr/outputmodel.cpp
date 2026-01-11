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

    m_outputs = workspace()->outputs();
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

void OutputModel::handleOutputAdded(LogicalOutput *output)
{
    beginInsertRows(QModelIndex(), m_outputs.count(), m_outputs.count());
    m_outputs.append(output);
    endInsertRows();
}

void OutputModel::handleOutputRemoved(LogicalOutput *output)
{
    const int index = m_outputs.indexOf(output);
    Q_ASSERT(index != -1);

    beginRemoveRows(QModelIndex(), index, index);
    m_outputs.removeAt(index);
    endRemoveRows();
}
