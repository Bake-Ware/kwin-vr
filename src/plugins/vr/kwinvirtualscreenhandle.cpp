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

    const bool needsRecreate = !m_output
        || m_params.size != newParams.size
        || m_params.name != newParams.name
        || m_params.description != newParams.description;

    m_params = newParams;

    if (needsRecreate) {
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

        setOutput(output);
    }

    {
        auto mode = std::make_shared<OutputMode>(m_output->pixelSize(), newParams.refreshRate,
                                                 OutputMode::Flags{OutputMode::Flag::Preferred} | OutputMode::Flag::Custom);
        OutputConfiguration config;
        auto changeSet = config.changeSet(m_output);
        changeSet->enabled = true;
        changeSet->mode = mode;
        changeSet->scale = newParams.scale;
        changeSet->scaleSetting = newParams.scale;
        changeSet->customModes = {CustomModeDefinition{m_output->pixelSize(), newParams.refreshRate, OutputMode::Flag::Preferred}};
        Workspace::self()->applyOutputConfiguration(config);
    }

    Q_EMIT paramsChanged();
}

} // namespace KWin
