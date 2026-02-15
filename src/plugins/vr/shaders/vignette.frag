/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

VARYING vec2 texcoord;

void MAIN()
{
    // Map UV (0..1) to centered coords (-1..1)
    vec2 centered = texcoord * 2.0 - 1.0;

    // Per-axis fade: ramp from 0 (inside) to 1 (edge)
    // fadeWidth is the fraction of viewport from each edge that fades (e.g. 0.15 = 15%)
    float edgeStart = 1.0 - fadeWidth * 2.0;
    float fadeX = smoothstep(edgeStart, 1.0, abs(centered.x));
    float fadeY = smoothstep(edgeStart, 1.0, abs(centered.y));

    // Use max for rectangular fade (strips along each edge)
    float fade = max(fadeX, fadeY);

    FRAGCOLOR = vec4(0.0, 0.0, 0.0, fade);
}
