/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#ifndef KWINASYNCREADBACK_H
#define KWINASYNCREADBACK_H

namespace KWin
{

/**
 * Per-surface state for async PBO-based DMA-BUF readback.
 * Uses primitive types so this header can be included without pulling in GL/EGL headers.
 * All fields are render-thread-only. GLuint = unsigned int, GLsync = struct __GLsync*.
 */
struct AsyncReadbackState {
    unsigned int pbo = 0;   ///< GLuint: GL pixel-pack buffer object
    void *fence = nullptr;  ///< GLsync: GL sync object (struct __GLsync*)
    int width = 0;
    int height = 0;
    bool hasAlpha = false;
    bool pending = false;
};

} // namespace KWin

#endif // KWINASYNCREADBACK_H
