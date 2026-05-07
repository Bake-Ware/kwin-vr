/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvrbridge.h"

namespace KWin
{

KwinVrBridge::KwinVrBridge(QObject *parent)
    : QObject(parent)
{
}

KwinVrBridge *KwinVrBridge::instance()
{
    static KwinVrBridge s_instance;
    return &s_instance;
}

bool KwinVrBridge::fallbackMode() const
{
    return m_fallbackMode;
}

void KwinVrBridge::setFallbackMode(bool fallback)
{
    if (m_fallbackMode == fallback) {
        return;
    }
    m_fallbackMode = fallback;
    Q_EMIT fallbackModeChanged();
}

} // namespace KWin
