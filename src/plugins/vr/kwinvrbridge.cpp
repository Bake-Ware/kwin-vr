/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvrbridge.h"

KwinVrBridge::KwinVrBridge(QObject *parent)
    : QObject(parent)
{
}

void KwinVrBridge::xrPing()
{
    Q_EMIT xrPingReceived();
}
