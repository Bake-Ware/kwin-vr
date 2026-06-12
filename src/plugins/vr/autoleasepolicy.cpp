/*
    SPDX-FileCopyrightText: 2026 bake

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "autoleasepolicy.h"

namespace KWin::AutoLeasePolicy
{

bool shouldRearm(const QStringList &configuredOutputs, const QList<OutputSnapshot> &outputs)
{
    if (configuredOutputs.isEmpty()) {
        return false;
    }
    for (const OutputSnapshot &output : outputs) {
        if (configuredOutputs.contains(output.name)) {
            return false;
        }
    }
    return true;
}

QStringList eligibleOutputs(const QStringList &configuredOutputs, const QList<OutputSnapshot> &outputs, int minWidth)
{
    QStringList eligible;
    for (const QString &name : configuredOutputs) {
        for (const OutputSnapshot &output : outputs) {
            if (output.name != name) {
                continue;
            }
            if (!output.leasingCapable || output.nonDesktop) {
                break;
            }
            // Only auto-lease when the display is in SBS mode (double-wide
            // resolution) — the glasses expose plain 1920x1080 otherwise.
            if (minWidth > 0 && output.width < minWidth) {
                break;
            }
            eligible.append(name);
            break;
        }
    }
    return eligible;
}

bool anyLeased(const QList<OutputSnapshot> &outputs)
{
    for (const OutputSnapshot &output : outputs) {
        if (output.leased) {
            return true;
        }
    }
    return false;
}

AutoStopAction autoStopAction(bool vrActive, bool sawLeaseWhileActive, const QList<OutputSnapshot> &outputs)
{
    if (!vrActive) {
        return AutoStopAction::None;
    }
    if (anyLeased(outputs)) {
        return AutoStopAction::RememberLease;
    }
    // Only lease-backed sessions auto-exit: a manually activated flat or
    // no-lease session never saw a lease and must not be killed by output
    // churn.
    return sawLeaseWhileActive ? AutoStopAction::Stop : AutoStopAction::None;
}

} // namespace KWin::AutoLeasePolicy
