/*
    SPDX-FileCopyrightText: 2026 bake

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "autoleasepolicy.h"

#include <QTest>

using namespace KWin;
using namespace KWin::AutoLeasePolicy;

// Pins the auto-lease / auto-start / auto-stop decision logic, in particular
// the replug lifecycle that can only be exercised end-to-end with a physical
// hotplug: the one-shot latch must re-arm when the configured output
// disappears, and a lease-backed VR session must stop when its last lease is
// gone — while a manually activated no-lease session must never be touched.

namespace
{

OutputSnapshot glassesSbs(bool leasable = false, bool leased = false)
{
    // Xreal Air on DP-2 in SBS mode (3840x1080)
    return {
        .name = QStringLiteral("DP-2"),
        .leasingCapable = true,
        .nonDesktop = false,
        .leasable = leasable,
        .leased = leased,
        .width = 3840,
    };
}

OutputSnapshot internalPanel()
{
    return {
        .name = QStringLiteral("eDP-1"),
        .leasingCapable = false,
        .nonDesktop = false,
        .leasable = false,
        .leased = false,
        .width = 1366,
    };
}

const QStringList kConfigured{QStringLiteral("DP-2")};
constexpr int kMinWidth = 3840;

} // namespace

class TestAutoLeasePolicy : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void eligibleRequiresPresence()
    {
        QVERIFY(eligibleOutputs(kConfigured, {internalPanel()}, kMinWidth).isEmpty());
        QCOMPARE(eligibleOutputs(kConfigured, {internalPanel(), glassesSbs()}, kMinWidth),
                 QStringList{QStringLiteral("DP-2")});
    }

    void eligibleRequiresLeasingCapability()
    {
        OutputSnapshot noLeaseCap = glassesSbs();
        noLeaseCap.leasingCapable = false;
        QVERIFY(eligibleOutputs(kConfigured, {noLeaseCap}, kMinWidth).isEmpty());
    }

    void eligibleRejectsNonDesktop()
    {
        OutputSnapshot nonDesktop = glassesSbs();
        nonDesktop.nonDesktop = true;
        QVERIFY(eligibleOutputs(kConfigured, {nonDesktop}, kMinWidth).isEmpty());
    }

    void eligibleGatesOnSbsWidth()
    {
        // Glasses in plain 1080p mirror mode must not be auto-leased
        OutputSnapshot mirrorMode = glassesSbs();
        mirrorMode.width = 1920;
        QVERIFY(eligibleOutputs(kConfigured, {mirrorMode}, kMinWidth).isEmpty());
        // minWidth <= 0 disables the gate
        QCOMPARE(eligibleOutputs(kConfigured, {mirrorMode}, 0),
                 QStringList{QStringLiteral("DP-2")});
    }

    void rearmOnlyWhenAllConfiguredGone()
    {
        // Output present (leased or not): keep the latch
        QVERIFY(!shouldRearm(kConfigured, {internalPanel(), glassesSbs(true, true)}));
        QVERIFY(!shouldRearm(kConfigured, {glassesSbs(true, false)}));
        // Output gone (unplugged): re-arm
        QVERIFY(shouldRearm(kConfigured, {internalPanel()}));
        QVERIFY(shouldRearm(kConfigured, {}));
        // No configuration: nothing to re-arm
        QVERIFY(!shouldRearm({}, {internalPanel()}));
    }

    void autoStopIgnoresInactiveSession()
    {
        QCOMPARE(autoStopAction(false, false, {}), AutoStopAction::None);
        QCOMPARE(autoStopAction(false, true, {}), AutoStopAction::None);
    }

    void autoStopMarksLeaseBackedSession()
    {
        QCOMPARE(autoStopAction(true, false, {glassesSbs(true, true)}),
                 AutoStopAction::RememberLease);
    }

    void autoStopNeverKillsNoLeaseSession()
    {
        // Manually activated VR (flat mode, debugging) never saw a lease —
        // output churn must not exit it.
        QCOMPARE(autoStopAction(true, false, {internalPanel()}), AutoStopAction::None);
        QCOMPARE(autoStopAction(true, false, {}), AutoStopAction::None);
    }

    void autoStopFiresWhenLeaseBackedSessionLosesLastLease()
    {
        QCOMPARE(autoStopAction(true, true, {internalPanel()}), AutoStopAction::Stop);
        QCOMPARE(autoStopAction(true, true, {}), AutoStopAction::Stop);
        // A surviving lease anywhere keeps the session alive
        QCOMPARE(autoStopAction(true, true, {glassesSbs(true, true)}),
                 AutoStopAction::RememberLease);
    }

    // The regression scenario verbatim: "drm and vr mode set to auto, works
    // the first time. Looks like it won't lease again after a replug."
    // Walks the policy functions in the exact order kwinvr.cpp's slots call
    // them across plug → lease → VR active → unplug → replug.
    void replugLifecycle()
    {
        bool triggered = false;
        bool active = false;
        bool sawLease = false;
        int leaseCycles = 0;

        // One outputsQueried/outputLeaseStateChanged event, mirroring the
        // tryAutoLease + checkAutoStopVr slot logic.
        auto onOutputsChanged = [&](const QList<OutputSnapshot> &outputs) {
            if (triggered && shouldRearm(kConfigured, outputs)) {
                triggered = false;
            }
            if (!triggered && !active
                && !eligibleOutputs(kConfigured, outputs, kMinWidth).isEmpty()) {
                triggered = true;
                leaseCycles++; // refreshLeases: monado restart + lease offer
            }
            switch (autoStopAction(active, sawLease, outputs)) {
            case AutoStopAction::RememberLease:
                sawLease = true;
                break;
            case AutoStopAction::Stop:
                sawLease = false;
                active = false;
                break;
            case AutoStopAction::None:
                break;
            }
        };

        // First plug: glasses appear in SBS mode → lease cycle starts
        onOutputsChanged({internalPanel(), glassesSbs()});
        QCOMPARE(leaseCycles, 1);

        // Monado takes the lease, VR auto-starts
        onOutputsChanged({internalPanel(), glassesSbs(true, true)});
        active = true;
        onOutputsChanged({internalPanel(), glassesSbs(true, true)});
        QVERIFY(sawLease);

        // Unplug while active: output gone → VR exits, latch re-arms
        onOutputsChanged({internalPanel()});
        QVERIFY(!active);
        QVERIFY(!triggered);
        QCOMPARE(leaseCycles, 1);

        // Replug: the full chain must run again (this was the bug — the
        // one-shot latch blocked every lease after the first)
        onOutputsChanged({internalPanel(), glassesSbs(true)});
        QCOMPARE(leaseCycles, 2);
        QVERIFY(triggered);
    }
};

QTEST_GUILESS_MAIN(TestAutoLeasePolicy)
#include "testautoleasepolicy.moc"
