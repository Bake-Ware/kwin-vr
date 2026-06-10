/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/
// Pins the WindowGroup data model + registry scaffold (#25, salvaged from
// acba70807b): lateral membership (no reparenting), centroid anchor math,
// and registry register/unregister/lookup semantics. Data-only — modes,
// thumbtack geometry, and lasso land with the #14 dock+stack timebox.

import QtQuick
import QtQuick3D
import QtTest

import "../../qml"

TestCase {
    name: "WindowGroup"

    Component { id: groupFactory; WindowGroup {} }
    Component { id: registryFactory; WindowGroupRegistry {} }
    Component { id: nodeFactory; Node {} }

    function makeNode(x, y, z) {
        return nodeFactory.createObject(null, { position: Qt.vector3d(x, y, z) })
    }

    // --- membership: lateral, deduplicated, null-safe ---
    function test_membership() {
        const g = groupFactory.createObject(null)
        const a = makeNode(0, 0, 0)
        const b = makeNode(10, 0, 0)

        compare(g.members.length, 0)
        verify(!g.hasMember(a))

        g.addMember(a)
        compare(g.members.length, 1)
        verify(g.hasMember(a))
        verify(!g.hasMember(b))

        // dedup: re-adding is a no-op
        g.addMember(a)
        compare(g.members.length, 1)

        // null-safe
        g.addMember(null)
        compare(g.members.length, 1)

        // membership is lateral — the window does NOT become a child
        g.addMember(b)
        compare(b.parent, null)

        // removing a non-member is a no-op
        g.removeMember(makeNode(0, 0, 0))
        compare(g.members.length, 2)

        g.removeMember(a)
        compare(g.members.length, 1)
        verify(!g.hasMember(a))
        verify(g.hasMember(b))

        g.destroy()
    }

    // --- anchor = centroid of member scenePositions ---
    function test_recomputeAnchor() {
        const g = groupFactory.createObject(null)

        // empty group: position untouched
        g.position = Qt.vector3d(7, 7, 7)
        g.recomputeAnchor()
        compare(g.position, Qt.vector3d(7, 7, 7))

        g.addMember(makeNode(0, 0, 0))
        g.addMember(makeNode(30, -60, 90))
        g.addMember(makeNode(60, 60, -30))
        g.recomputeAnchor()
        compare(g.position, Qt.vector3d(30, 0, 20))

        g.destroy()
    }

    // --- registry: register assigns unique ids, double-register no-ops ---
    function test_registryRegister() {
        const reg = registryFactory.createObject(null)
        const g1 = groupFactory.createObject(null)
        const g2 = groupFactory.createObject(null)

        compare(reg.registerGroup(null), null)
        compare(reg.groups.length, 0)

        reg.registerGroup(g1)
        verify(g1.groupId !== "", "register assigns an id")
        compare(reg.groups.length, 1)
        compare(reg.findById(g1.groupId), g1)

        // double-register is a no-op
        reg.registerGroup(g1)
        compare(reg.groups.length, 1)

        reg.registerGroup(g2)
        verify(g2.groupId !== g1.groupId, "ids are unique")
        compare(reg.groups.length, 2)

        // explicit ids are preserved
        const g3 = groupFactory.createObject(null, { groupId: "wg_explicit" })
        reg.registerGroup(g3)
        compare(reg.findById("wg_explicit"), g3)

        reg.destroy()
    }

    // --- registry: unregister + findContaining ---
    function test_registryLookup() {
        const reg = registryFactory.createObject(null)
        const g = groupFactory.createObject(null)
        const member = makeNode(0, 0, 0)
        const stranger = makeNode(1, 1, 1)
        g.addMember(member)
        reg.registerGroup(g)

        compare(reg.findContaining(member), g)
        compare(reg.findContaining(stranger), null)
        compare(reg.findContaining(null), null)

        reg.unregisterGroup(g.groupId)
        compare(reg.groups.length, 0)
        compare(reg.findById(g.groupId), null)
        compare(reg.findContaining(member), null)

        // unregistering an unknown id is a no-op
        reg.unregisterGroup("wg_nope")
        compare(reg.groups.length, 0)

        reg.destroy()
    }

    // --- registry signals fire on state change ---
    function test_registrySignals() {
        const reg = registryFactory.createObject(null)
        const registeredSpy = signalSpy.createObject(null, { target: reg, signalName: "groupRegistered" })
        const unregisteredSpy = signalSpy.createObject(null, { target: reg, signalName: "groupUnregistered" })

        const g = groupFactory.createObject(null)
        reg.registerGroup(g)
        compare(registeredSpy.count, 1)

        // no signal on the no-op double-register
        reg.registerGroup(g)
        compare(registeredSpy.count, 1)

        reg.unregisterGroup(g.groupId)
        compare(unregisteredSpy.count, 1)

        // no signal on the no-op unknown unregister
        reg.unregisterGroup("wg_nope")
        compare(unregisteredSpy.count, 1)

        reg.destroy()
    }

    Component { id: signalSpy; SignalSpy {} }
}
