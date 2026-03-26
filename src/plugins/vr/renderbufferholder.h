/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include "core/graphicsbuffer.h"
#include "core/graphicsbufferview.h"

#include <optional>

namespace KWin
{

// Holds a GraphicsBuffer ref and (for shm/single-pixel buffers) its mmap view
// alive through the async XR render phase.
class RenderBufferHolder
{
public:
    void reset(GraphicsBuffer *buf = nullptr);
    GraphicsBufferView *view();

private:
    GraphicsBufferRef m_ref;
    std::optional<GraphicsBufferView> m_view;
};

} // namespace KWin
