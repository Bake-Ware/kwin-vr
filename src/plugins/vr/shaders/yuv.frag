/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

VARYING vec2 texcoord;

void MAIN()
{
    vec2 uv_coord = uvTransform.xz + texcoord * uvTransform.yw;
    float y = texture(yTexture, uv_coord).r;
    vec2 uv = texture(uvTexture, uv_coord).rg;
    FRAGCOLOR = clamp(yuvToRgb * vec4(y, uv.r, uv.g, 1.0), 0.0, 1.0);
}
