/*
    SPDX-FileCopyrightText: 2026 bake

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QList>
#include <QString>
#include <QStringList>

namespace KWin
{

// Pure decision logic for the auto-lease / auto-start / auto-stop chain in
// KwinVr (kwinvr.cpp). Kept free of backend types so the replug lifecycle —
// which needs a physical hotplug on real hardware — can be pinned by a plain
// unit test (autotests/testautoleasepolicy.cpp).
namespace AutoLeasePolicy
{

// What the policy needs to know about one backend output.
struct OutputSnapshot
{
    QString name;
    bool leasingCapable = false;
    bool nonDesktop = false;
    bool leasable = false;
    bool leased = false; // isLeased() || isLeasePending()
    int width = 0; // current mode width (SBS gate)
};

// Replug re-arm: the auto-lease latch is one-shot per *connection*, not per
// session. True when every configured output has disappeared from the
// backend (glasses unplugged) — the caller then clears the latch so the next
// hotplug runs the full lease+autostart chain again.
bool shouldRearm(const QStringList &configuredOutputs, const QList<OutputSnapshot> &outputs);

// Configured outputs that are present and eligible for auto-leasing right
// now: lease-capable desktop outputs in SBS mode (width >= minWidth;
// minWidth <= 0 disables the width check).
QStringList eligibleOutputs(const QStringList &configuredOutputs, const QList<OutputSnapshot> &outputs, int minWidth);

bool anyLeased(const QList<OutputSnapshot> &outputs);

// Auto-stop transition for one output-change event.
enum class AutoStopAction {
    None, // nothing to do
    RememberLease, // a lease is live while VR is active — mark the session lease-backed
    Stop, // a lease-backed session lost its last lease — exit VR mode
};
AutoStopAction autoStopAction(bool vrActive, bool sawLeaseWhileActive, const QList<OutputSnapshot> &outputs);

} // namespace AutoLeasePolicy
} // namespace KWin
