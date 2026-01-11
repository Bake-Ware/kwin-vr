/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

VARYING vec2 texcoord;

void MAIN()
{
    vec2 uv_coord = uvTransform.xz + texcoord * uvTransform.yw;
    FRAGCOLOR = texture(baseColorMap, uv_coord);
}
