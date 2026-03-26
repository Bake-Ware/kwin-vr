/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "core/output.h"
#include <QAbstractListModel>
#include <QtQml/qqmlregistration.h>

namespace KWin
{
class OutputModel : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
public:
    enum Roles {
        OutputRole = Qt::UserRole + 1,
    };

    explicit OutputModel(QObject *parent = nullptr);

    QHash<int, QByteArray> roleNames() const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;

private:
    void handleOutputAdded(LogicalOutput *output);
    void handleOutputRemoved(LogicalOutput *output);

    QList<LogicalOutput *> m_outputs;
};

} // namespace KWin
