/*
    SPDX-FileCopyrightText: 2026 bake

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "vrpinregistry.h"

#include "window.h"

namespace KWin
{

VrPinRegistry *VrPinRegistry::instance()
{
    static VrPinRegistry *s_instance = new VrPinRegistry();
    return s_instance;
}

VrPinRegistry::VrPinRegistry(QObject *parent)
    : QObject(parent)
{
}

bool VrPinRegistry::isPinned(Window *window) const
{
    return window && m_pinned.contains(window);
}

void VrPinRegistry::toggle(Window *window)
{
    if (!window) {
        return;
    }
    if (m_pinned.contains(window)) {
        m_pinned.remove(window);
    } else {
        m_pinned.insert(window);
        connect(window, &QObject::destroyed, this, [this, window] {
            if (m_pinned.remove(window)) {
                ++m_revision;
                Q_EMIT pinnedChanged();
            }
        });
    }
    ++m_revision;
    Q_EMIT pinnedChanged();
}

} // namespace KWin
