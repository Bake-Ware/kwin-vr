/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <epoxy/egl.h>
#include <epoxy/gl.h>

#include "core/graphicsbuffer.h"
#include "wayland/surface.h"

#include <QList>
#include <QQuickWindow>
#include <QSGImageNode>
#include <rhi/qrhi.h>

namespace KWin
{

struct QtTexturePair
{
    GLuint glTexture = 0;
    QSGTexture *qtTexture = nullptr;
};

struct GraphicsBufferTextures
{
    QtTexturePair planeTextures[4];
    int planeCount = 0;
    void release();
};

QList<uint32_t> supportedDmabufFormats();
GraphicsBufferTextures loadGraphicsBufferToQSGTextures(GraphicsBuffer *buf, QQuickWindow *win);

} // namespace KWin
