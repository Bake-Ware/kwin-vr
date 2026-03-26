/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "kwinvrhoveredwindowresolver.h"

#include "input.h"
#include "pointer_input.h"
#include "window.h"

namespace KWin
{
KwinVrHoveredWindowResolver::KwinVrHoveredWindowResolver(QObject *parent)
    : QObject(parent)
{
    if (input() && input()->pointer()) {
        input()->pointer()->setHoveredWindowFinder([this]() -> Window * {
            auto *window = m_hoveredWindow.data();
            if (!window || window->isDeleted()) {
                return nullptr;
            }
            return window;
        });
    }
}

KwinVrHoveredWindowResolver::~KwinVrHoveredWindowResolver()
{
    if (input() && input()->pointer()) {
        input()->pointer()->setHoveredWindowFinder(nullptr);
    }
}

Window *KwinVrHoveredWindowResolver::hoveredWindow() const
{
    auto *window = m_hoveredWindow.data();
    if (!window || window->isDeleted()) {
        return nullptr;
    }
    return window;
}

void KwinVrHoveredWindowResolver::setHoveredWindow(Window *window)
{
    if (window && window->isDeleted()) {
        window = nullptr;
    }
    if (m_hoveredWindow == window) {
        return;
    }

    m_hoveredWindow = window;
    input()->pointer()->update();
    Q_EMIT hoveredWindowChanged();
}
} // namespace KWin
