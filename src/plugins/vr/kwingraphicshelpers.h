/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef KWINGRAPHICSHELPERS_H
#define KWINGRAPHICSHELPERS_H

#include <epoxy/egl.h>
#include <epoxy/gl.h>

#include "core/graphicsbuffer.h"
#include "kwinasyncreadback.h"
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

/**
 * Initiate an async DMA-BUF readback via a PBO.
 * Non-blocking: glReadPixels with a bound PBO returns immediately (DMA to PBO).
 * Returns false if readback could not be started (e.g. already pending, unsupported format).
 * Must be called from the render thread.
 */
bool startEglDmaBufReadback(AsyncReadbackState &state, GraphicsBuffer *buf);

/**
 * Check whether a previously started readback has completed.
 * If complete, maps the PBO, creates a QSGTexture, and returns it.
 * Returns nullptr if the readback is still in flight.
 * Must be called from the render thread.
 */
QSGTexture *tryHarvestEglReadback(AsyncReadbackState &state, QQuickWindow *win);

/**
 * Cancel a pending readback and release GL resources (PBO, fence).
 * Safe to call even if no readback is pending.
 * Must be called from the render thread.
 */
void cancelEglReadback(AsyncReadbackState &state);

}; //
#endif // KWINGRAPHICSHELPERS_H
