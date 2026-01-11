/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvirtualscreenhandle.h"
#include <QTimer>
#include <core/output.h>
#include <core/outputbackend.h>
#include <core/outputconfiguration.h>
#include <workspace.h>

using namespace KWin;
KwinVirtualScreenHandle::KwinVirtualScreenHandle(QObject *parent)
    : QObject{parent}
{
}

KwinVirtualScreenHandle::~KwinVirtualScreenHandle()
{
    if (m_output) {
        auto output = m_output;
        m_output = nullptr;
        kwinApp()->outputBackend()->removeVirtualOutput(output);
    }
}

BackendOutput *KwinVirtualScreenHandle::output() const
{
    return m_output;
}

void KwinVirtualScreenHandle::setOutput(KWin::BackendOutput *newOutput)
{
    if (m_output == newOutput)
        return;

    m_output = newOutput;
    Q_EMIT outputChanged();
}

QSize KwinVirtualScreenParams::size() const
{
    return m_size;
}

void KwinVirtualScreenParams::setSize(const QSize &newSize)
{
    m_size = newSize;
}

QString KwinVirtualScreenParams::name() const
{
    return m_name;
}

void KwinVirtualScreenParams::setName(const QString &newName)
{
    m_name = newName;
}

QString KwinVirtualScreenParams::description() const
{
    return m_description;
}

void KwinVirtualScreenParams::setDescription(const QString &newDescription)
{
    m_description = newDescription;
}

qreal KwinVirtualScreenParams::scale() const
{
    return m_scale;
}

void KwinVirtualScreenParams::setScale(qreal newScale)
{
    m_scale = newScale;
}

KwinVirtualScreenParams KwinVirtualScreenHandle::params() const
{
    return m_params;
}

void KwinVirtualScreenHandle::setParams(const KWin::KwinVirtualScreenParams &newParams)
{
    if (
        m_params.size() == newParams.size() && m_params.name() == newParams.name() && m_params.description() == newParams.description() && m_params.scale() == newParams.scale()) {
        return;
    }
    m_params = newParams;

    if (m_output) {
        auto output = m_output;
        setOutput(nullptr);
        kwinApp()->outputBackend()->removeVirtualOutput(output);
    }

    auto output = kwinApp()->outputBackend()->createVirtualOutput(
        newParams.name(),
        newParams.description(),
        newParams.size(),
        newParams.scale());

    OutputConfiguration config;
    config.changeSet(output)->enabled = true;
    config.changeSet(output)->scale = newParams.scale();
    Workspace::self()->applyOutputConfiguration(config);

    setOutput(output);
    Q_EMIT paramsChanged();
}
