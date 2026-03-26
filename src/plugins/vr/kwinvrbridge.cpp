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

} // namespace KWin
