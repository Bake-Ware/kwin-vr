/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "kwincompat.h"

#include <QObject>
#include <QQmlEngine>
#include <QSize>

namespace KWin
{
class KwinVirtualScreenParams
{
    Q_GADGET
    Q_PROPERTY(QSize size MEMBER size FINAL)
    Q_PROPERTY(QString name MEMBER name FINAL)
    Q_PROPERTY(QString description MEMBER description FINAL)
    Q_PROPERTY(qreal scale MEMBER scale FINAL)
    QML_VALUE_TYPE(kwinVirtualScreenParams)
public:
    bool operator==(const KwinVirtualScreenParams &other) const
    {
        return size == other.size && name == other.name
            && description == other.description && qFuzzyCompare(scale, other.scale);
    }

    QString name;
    QString description;
    QSize size;
    qreal scale = 1.0;
};

/** Creates a virtual output (virtual screen) in KWin. */
class KwinVirtualScreenHandle : public QObject
{
    Q_OBJECT
    Q_PROPERTY(KWin::BackendOutput *output READ output NOTIFY outputChanged FINAL)
    Q_PROPERTY(KWin::KwinVirtualScreenParams params READ params WRITE setParams NOTIFY paramsChanged FINAL)
    QML_ELEMENT
public:
    explicit KwinVirtualScreenHandle(QObject *parent = nullptr);
    ~KwinVirtualScreenHandle() override;
    BackendOutput *output() const;

    KwinVirtualScreenParams params() const;
    void setParams(const KwinVirtualScreenParams &newParams);

Q_SIGNALS:
    void outputChanged();
    void paramsChanged();

private:
    void setOutput(BackendOutput *newOutput);

    BackendOutput *m_output = nullptr;
    KwinVirtualScreenParams m_params;
};

} // namespace KWin
