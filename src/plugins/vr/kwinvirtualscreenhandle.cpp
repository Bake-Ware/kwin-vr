/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvirtualscreenhandle.h"
#include "core/output.h"
#include "core/outputbackend.h"
#include "core/outputconfiguration.h"
#include "workspace.h"

namespace KWin
{

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

void KwinVirtualScreenHandle::setOutput(BackendOutput *newOutput)
{
    if (m_output == newOutput) {
        return;
    }

    m_output = newOutput;
    Q_EMIT outputChanged();
}

KwinVirtualScreenParams KwinVirtualScreenHandle::params() const
{
    return m_params;
}

void KwinVirtualScreenHandle::setParams(const KwinVirtualScreenParams &newParams)
{
    if (m_params == newParams) {
        return;
    }
    m_params = newParams;

    if (m_output) {
        auto output = m_output;
        setOutput(nullptr);
        kwinApp()->outputBackend()->removeVirtualOutput(output);
    }

    auto output = kwinApp()->outputBackend()->createVirtualOutput(
        newParams.name,
        newParams.description,
        newParams.size,
        newParams.scale);

    OutputConfiguration config;
    config.changeSet(output)->enabled = true;
    config.changeSet(output)->scale = newParams.scale;
    Workspace::self()->applyOutputConfiguration(config);

    setOutput(output);
    Q_EMIT paramsChanged();
}

} // namespace KWin
