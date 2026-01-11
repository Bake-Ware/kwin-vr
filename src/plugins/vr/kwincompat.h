/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

// This file is needed to build this plugin with KWin 6.5
// Once 6.5 is dead it will be removed

#if __has_include(<core/backendoutput.h>)
// Newer KWin versions (6.6+)
#include <core/backendoutput.h>
#include <core/output.h>

// Helper to compare/access backend from logical output across versions
inline KWin::BackendOutput *kwinGetBackendOutput(KWin::LogicalOutput *o)
{
    return o->backendOutput();
}
#else
// Older KWin versions
#include <core/output.h>

namespace KWin
{
using LogicalOutput = Output;
using BackendOutput = Output;
}

inline KWin::BackendOutput *kwinGetBackendOutput(KWin::LogicalOutput *o)
{
    return o;
}
#endif
