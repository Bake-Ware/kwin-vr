/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

VARYING vec2 texcoord;

void MAIN()
{
    texcoord = UV0;
    // Full-screen quad: map UV (0..1) to clip space (-1..1).
    // This covers the entire viewport regardless of camera FOV or model transform.
    POSITION = vec4(UV0 * 2.0 - 1.0, 0.0, 1.0);
}
