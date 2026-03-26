/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "renderbufferholder.h"

namespace KWin
{

void RenderBufferHolder::reset(GraphicsBuffer *buf)
{
    m_view.reset();
    m_ref = buf;
    if (buf && (buf->shmAttributes() || buf->singlePixelAttributes())) {
        m_view.emplace(buf);
    }
}

GraphicsBufferView *RenderBufferHolder::view()
{
    return m_view ? &*m_view : nullptr;
}

} // namespace KWin
