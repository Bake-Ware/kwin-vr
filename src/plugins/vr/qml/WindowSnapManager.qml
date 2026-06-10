/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
 * WindowSnapManager — natural-drag dock + stack (#14).
 *
 * Ray-pick based, mirrors KwinPseudoOutputMirror's lookForScreenToPut pattern.
 * While a VR-floating window is grabbed, watch picking.lastAllPicks for the
 * first VR-window hit that isn't the dragged one. Use ray hit UV on that
 * target to pick action (edge zones → snap, center → stack), expose telegraph
 * landing pose, lay dragged on target's plane during drag, commit on release.
 */

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

import "WindowSnapLogic.js" as SnapLogic

QtObject {
    id: root

    // Values mirror WindowSnapLogic.js Action* constants (pure logic +
    // qmltest live there; this enum is the QML-facing name).
    enum Action { None, SnapLeft, SnapRight, SnapAbove, SnapBelow, Stack }

    required property Xray xray
    required property var windowsRepeater   // kept for compat; unused
    required property VrPicking picking
    required property var kwinInput         // KwinVrInputDevice — for click/release detection

    // UV edge band — within this fraction of an edge → snap to that side.
    property real edgeBand: 0.25

    property Node currentTarget: null
    property int currentAction: WindowSnapManager.Action.None

    // Landing pose for the telegraph ghost (target-local).
    property vector3d landingLocalOffset: Qt.vector3d(0, 0, 0)
    property size landingSize: Qt.size(0, 0)

    property var _lastDragged: null
    // Members reparented under grabbed during drag (group-rigid via Qt
    // transform inheritance). Array of { window: Node, oldParent: Node }.
    property var _stackDragMembers: null
    // True if a grab/drag started between the current trigger press and its
    // release. Cleared on press, set when xray.grabbedObject becomes set.
    property bool _dragStartedThisPress: false

    function actionName(a) {
        switch (a) {
            case WindowSnapManager.Action.SnapLeft:  return "SnapLeft"
            case WindowSnapManager.Action.SnapRight: return "SnapRight"
            case WindowSnapManager.Action.SnapAbove: return "SnapAbove"
            case WindowSnapManager.Action.SnapBelow: return "SnapBelow"
            case WindowSnapManager.Action.Stack:     return "Stack"
            default: return "None"
        }
    }

    function _setIntent(target, action) {
        if (currentTarget === target && currentAction === action)
            return
        currentTarget = target
        currentAction = action
        _computeLanding()
        if (target) {
            const klass = target.client && target.client.resourceClass ? target.client.resourceClass : "?"
            console.log(Logger.kwinvr, "Snap intent:", actionName(action), "→", klass)
        } else if (action === WindowSnapManager.Action.None) {
            console.log(Logger.kwinvr, "Snap intent: none")
        }
    }

    // Count existing stack members on target → next stack index for a new add.
    // Excludes `dragged` so re-stacking the same window doesn't double-count.
    function _nextStackIndex(target, dragged) {
        if (!target || !root.windowsRepeater) return 1
        let max = 0
        const n = root.windowsRepeater.count
        for (let i = 0; i < n; ++i) {
            const w = root.windowsRepeater.objectAt(i)
            if (!w || w === target || w === dragged) continue
            if (w.stackedOnto === target && w.stackIndex > max)
                max = w.stackIndex
        }
        return max + 1
    }

    // Walk stackedOnto chain to bottom — snapping to a stacked window should
    // snap relative to the stack root.
    function _stackRoot(w) {
        let n = w
        while (n && n.stackedOnto) n = n.stackedOnto
        return n
    }

    // Decrement stackIndex of siblings above `w` on its current stack root,
    // then clear w's own stack ref. Run before assigning a new stack state.
    function _detachFromStack(w) {
        if (!w || !w.stackedOnto) return
        const oldRoot = w.stackedOnto
        const oldIdx = w.stackIndex
        w.stackedOnto = null
        w.stackIndex = 0
        if (!root.windowsRepeater) return
        const n = root.windowsRepeater.count
        for (let i = 0; i < n; ++i) {
            const sib = root.windowsRepeater.objectAt(i)
            if (!sib || sib === w) continue
            if (sib.stackedOnto === oldRoot && sib.stackIndex > oldIdx)
                sib.stackIndex = sib.stackIndex - 1
        }
        _repositionStack(oldRoot)
    }

    // Re-write scene pose for every stack member of `rootW`, using current
    // stackIndex values. Used after promote/detach to make cascade visible.
    function _repositionStack(rootW) {
        if (!rootW || !root.windowsRepeater) return
        const n = root.windowsRepeater.count
        for (let i = 0; i < n; ++i) {
            const w = root.windowsRepeater.objectAt(i)
            if (!w || w.stackedOnto !== rootW) continue
            const r = _computeLandingPose(rootW, w, WindowSnapManager.Action.Stack, w.stackIndex)
            const sceneP = rootW.mapPositionToScene(r.offset)
            KwinVrHelpers.setNodePositionFromScene(w, sceneP)
            KwinVrHelpers.setNodeRotationFromScene(w, rootW.sceneRotation)
        }
    }

    // Promote a window to the top of its cascade.
    //   * member click → shift members above it down by 1, member takes top idx
    //   * root click   → rotate stack: current top member becomes new root,
    //                    old root becomes top member with idx=max
    function promoteStackMember(w) {
        if (!w || !root.windowsRepeater) return
        const n = root.windowsRepeater.count

        if (w.stackedOnto) {
            // Member case.
            const rootW = w.stackedOnto
            const oldIdx = w.stackIndex
            let max = 0
            for (let i = 0; i < n; ++i) {
                const sib = root.windowsRepeater.objectAt(i)
                if (!sib || sib === w) continue
                if (sib.stackedOnto === rootW && sib.stackIndex > max)
                    max = sib.stackIndex
            }
            if (oldIdx >= max) return
            for (let i = 0; i < n; ++i) {
                const sib = root.windowsRepeater.objectAt(i)
                if (!sib || sib === w) continue
                if (sib.stackedOnto === rootW && sib.stackIndex > oldIdx)
                    sib.stackIndex = sib.stackIndex - 1
            }
            w.stackIndex = max
            _repositionStack(rootW)
            return
        }

        // Root case. Find current top member; swap roles.
        let topMember = null
        let max = 0
        for (let i = 0; i < n; ++i) {
            const sib = root.windowsRepeater.objectAt(i)
            if (!sib || sib === w) continue
            if (sib.stackedOnto === w && sib.stackIndex > max) {
                max = sib.stackIndex
                topMember = sib
            }
        }
        if (!topMember) return  // root with no members; nothing to promote
        const oldRoot = w
        // Anchor the stack visually at oldRoot's pose: move topMember there
        // BEFORE swapping roles, so cascade after reposition stays in place.
        const anchorPos = oldRoot.scenePosition
        const anchorRot = oldRoot.sceneRotation
        KwinVrHelpers.setNodePositionFromScene(topMember, anchorPos)
        KwinVrHelpers.setNodeRotationFromScene(topMember, anchorRot)
        // Re-anchor everything onto topMember.
        topMember.stackedOnto = null
        topMember.stackIndex = 0
        for (let i = 0; i < n; ++i) {
            const sib = root.windowsRepeater.objectAt(i)
            if (!sib || sib === topMember) continue
            if (sib.stackedOnto === oldRoot)
                sib.stackedOnto = topMember
        }
        // oldRoot becomes a member at top index.
        oldRoot.stackedOnto = topMember
        oldRoot.stackIndex = max
        _repositionStack(topMember)
    }

    // Compute landing pose (target-local). Used by both telegraph + commit.
    // stackIdx multiplies the cascade offset for stack action (1 = first
    // child, 2 = second, …). Pass null/0 for non-stack telegraphs.
    // Returns { offset: vector3d, size: size, landW, landH }.
    function _computeLandingPose(target, dragged, action, stackIdx) {
        if (!target || !target.client || !dragged || !dragged.client
            || action === WindowSnapManager.Action.None) {
            return { offset: Qt.vector3d(0, 0, 0), size: Qt.size(0, 0), landW: 0, landH: 0 }
        }
        const tg = target.client.frameGeometry
        const dg = dragged.client.frameGeometry
        // Use zSurfaceMarginTop for both plane lift and stack cascade step
        // — keeps offsets small and consistent with surface separation unit.
        // Math lives in WindowSnapLogic.js (pure, qmltest-pinned).
        const r = SnapLogic.landingPose(
            tg.width / target.ppu, tg.height / target.ppu,
            dg.width / dragged.ppu, dg.height / dragged.ppu,
            KWinVRConfig.zSurfaceMarginTop, action, stackIdx)
        return { offset: Qt.vector3d(r.x, r.y, r.z), size: Qt.size(r.landW, r.landH),
                 landW: r.landW, landH: r.landH }
    }

    function _computeLanding() {
        const dragged = xray.grabbedObject as KwinApplicationWindow
        const idx = (currentAction === WindowSnapManager.Action.Stack)
                  ? _nextStackIndex(currentTarget, dragged) : 0
        const r = _computeLandingPose(currentTarget, dragged, currentAction, idx)
        landingLocalOffset = r.offset
        landingSize = r.size
    }

    // Trace a pick result up to the owning KwinApplicationWindow.
    // KwinTransientWindow sets grabHandle = its KwinApplicationWindow root.
    // If the resolved window is itself stacked on another, walk to the stack
    // root so all snap actions land relative to the bottommost window.
    function _resolveTargetWindow(pick) {
        const obj = pick.objectHit ?? root.picking.getHoveredNodeFromItem(pick.itemHit)
        if (!obj) return null
        let win = null
        if (obj.grabHandle && obj.grabHandle.client && obj.grabHandle.client.vr) {
            win = obj.grabHandle as KwinApplicationWindow
        } else {
            let n = obj
            while (n) {
                if (n.client && n.windowDataModel !== undefined) {
                    win = n as KwinApplicationWindow
                    break
                }
                n = n.parent
            }
        }
        return win ? _stackRoot(win) : null
    }

    // UV → snap action. UV here has y=0 at BOTTOM (texture convention here).
    // Decision table in WindowSnapLogic.js (pure, qmltest-pinned).
    function _actionFromUv(u, v) {
        return SnapLogic.actionFromUv(u, v, root.edgeBand)
    }

    function _scan() {
        const dragged = xray.grabbedObject as KwinApplicationWindow
        if (!dragged || !dragged.client || !dragged.client.vr) {
            _setIntent(null, WindowSnapManager.Action.None)
            return
        }
        _lastDragged = dragged

        // Find first ray hit that's a VR window not in dragged's own stack.
        // (Skip own-stack — dragged + its members share a stack root, and
        // adhering to a stack-mate creates a feedback loop since members are
        // reparented under dragged during drag.)
        const draggedRoot = _stackRoot(dragged)
        let target = null
        let hitScene = null
        const picks = root.picking.lastAllPicks
        for (const pick of picks) {
            const cand = _resolveTargetWindow(pick)
            if (!cand) continue
            if (_stackRoot(cand) === draggedRoot) continue
            if (!cand.client || !cand.client.vr) continue
            target = cand
            hitScene = pick.scenePosition
            break
        }

        if (!target) {
            _setIntent(null, WindowSnapManager.Action.None)
            return
        }

        // Recompute UV against ROOT plane — picks may land on any stack
        // member, so per-pick uvPosition jitters. Mapping pick.scenePosition
        // into root local stabilizes UV across stacked overlap.
        const tg = target.client.frameGeometry
        const tw = tg.width / target.ppu
        const th = tg.height / target.ppu
        const localHit = target.mapPositionFromScene(hitScene)
        const u = localHit.x / tw + 0.5
        const v = localHit.y / th + 0.5
        const action = _actionFromUv(u, v)
        _setIntent(target, action)

        // Surface adhesion: lay dragged on root plane at recomputed UV pos.
        const lx = localHit.x
        const ly = localHit.y
        const zFwd = KWinVRConfig.zSurfaceMarginTop
        const stuckLocal = Qt.vector3d(lx, ly, zFwd)
        const newScene = target.mapPositionToScene(stuckLocal)
        // Direct writes for this frame (Xray.applyRelativePose ran before us).
        // Match target's plane: position on surface + same rotation.
        KwinVrHelpers.setNodePositionFromScene(dragged, newScene)
        KwinVrHelpers.setNodeRotationFromScene(dragged, target.sceneRotation)
        // Capture both into xray.grabbedObjectPose so subsequent apply calls
        // preserve them (otherwise xray clobbers per frame).
        xray.grabbedObjectPose = KwinVrHelpers.getRelativePose(xray, dragged)
    }

    function _commitSnap(dragged, target, action) {
        if (!dragged || !target || !dragged.client || !target.client) return

        const dg = dragged.client.frameGeometry
        // Detach from any prior stack first — clears state + decrements
        // siblings so the next index calc is correct.
        _detachFromStack(dragged)
        const stackIdx = (action === WindowSnapManager.Action.Stack)
                       ? _nextStackIndex(target, dragged) : 0
        const r = _computeLandingPose(target, dragged, action, stackIdx)

        if (!dragged.preSnapGeom)
            dragged.preSnapGeom = Qt.size(dg.width, dg.height)

        if (action === WindowSnapManager.Action.Stack) {
            dragged.stackedOnto = target
            dragged.stackIndex = stackIdx
        }

        const dw_px = r.landW * target.ppu - dg.width
        const dh_px = r.landH * target.ppu - dg.height
        if (Math.abs(dw_px) > 0.5 || Math.abs(dh_px) > 0.5)
            KwinVrHelpers.windowResize(dragged.client, dw_px, dh_px)

        const landScene = target.mapPositionToScene(r.offset)
        KwinVrHelpers.setNodePositionFromScene(dragged, landScene)
        KwinVrHelpers.setNodeRotationFromScene(dragged, target.sceneRotation)

        const tklass = target.client.resourceClass || "?"
        console.log(Logger.kwinvr, "Snap commit:", actionName(action), "→", tklass,
                    "stackIdx=", stackIdx)
    }

    // Trigger scan on every ray-pick update (mirrors lookForScreenToPut).
    readonly property Connections _scanWatcher: Connections {
        target: root.picking
        enabled: root.xray && root.xray.grabbedObject !== null
        function onLastAllPicksChanged() { root._scan() }
    }

    // Reparent stack-mates under grabbed at grab-start so Qt's transform
    // inheritance carries them with grabbed automatically. Avoids fighting
    // parent rotations (e.g. VrFollowMode) that would otherwise compound
    // when re-applying captured offsets.
    function _captureStackDrag(grabbed) {
        _stackDragMembers = null
        if (!grabbed || !root.windowsRepeater) return
        // Only act on already-VR-floating windows. Skips the
        // pseudomirror→VR detach path.
        if (!grabbed.client || !grabbed.client.vr) return
        // Only when grabbed is a stack ROOT — group-rigid drag follows a root.
        // Member-grab is a single-window detach; other stack-mates stay put.
        if (grabbed.stackedOnto) return
        const n = root.windowsRepeater.count
        const list = []
        for (let i = 0; i < n; ++i) {
            const w = root.windowsRepeater.objectAt(i)
            if (!w || w === grabbed) continue
            if (w.stackedOnto !== grabbed) continue
            const oldParent = w.parent
            const pose = KwinVrHelpers.getRelativePose(grabbed, w)
            w.parent = grabbed
            w.position = pose.position
            w.rotation = pose.rotation
            list.push({ window: w, oldParent: oldParent })
        }
        if (list.length > 0) _stackDragMembers = list
    }

    function _releaseStackDrag() {
        if (!_stackDragMembers) return
        for (const m of _stackDragMembers) {
            const scenePos = m.window.scenePosition
            const sceneRot = m.window.sceneRotation
            m.window.parent = m.oldParent
            KwinVrHelpers.setNodePositionFromScene(m.window, scenePos)
            KwinVrHelpers.setNodeRotationFromScene(m.window, sceneRot)
        }
        _stackDragMembers = null
    }

    // Watch grabbed window's `client.vr`. If it flips to false mid-drag
    // (root snaps to pseudomirror), members must be detached from grabbed
    // before its state machine reparents to the pseudo output, otherwise
    // members get dragged into the screen frame.
    readonly property Connections _grabbedVrWatcher: Connections {
        // ?? null: world-grab handle has no `client` — undefined would not
        // coerce to QObject* ("Unable to assign [undefined]").
        target: (root.xray && root.xray.grabbedObject
                ? root.xray.grabbedObject.client : null) ?? null
        enabled: root.xray && root.xray.grabbedObject !== null
                 && root._stackDragMembers !== null
        function onVrChanged() {
            const c = root.xray.grabbedObject ? root.xray.grabbedObject.client : null
            if (!c || c.vr) return
            // Root went to pseudomirror — send each stack member to its
            // own screen too. Snapshot members first since _releaseStackDrag
            // clears the list.
            const members = root._stackDragMembers.slice()
            root._releaseStackDrag()
            for (const m of members) {
                if (!m.window) continue
                m.window.stackedOnto = null
                m.window.stackIndex = 0
                if (m.window.client) m.window.client.vr = false
            }
        }
    }

    // Track trigger press/release (the only deterministic click signal). On
    // release without a drag → it was a click → promote focused window if
    // part of a stack.
    readonly property Connections _clickWatcher: Connections {
        target: root.kwinInput
        function onLeftButtonChanged() {
            if (root.kwinInput.leftButton) {
                root._dragStartedThisPress = false
            } else if (!root._dragStartedThisPress) {
                root._promoteFocusedIfStacked()
            }
        }
    }

    function _hasStackMembers(w) {
        if (!w || !root.windowsRepeater) return false
        const n = root.windowsRepeater.count
        for (let i = 0; i < n; ++i) {
            const sib = root.windowsRepeater.objectAt(i)
            if (sib && sib.stackedOnto === w) return true
        }
        return false
    }

    function _promoteFocusedIfStacked() {
        if (!root.windowsRepeater) return
        const n = root.windowsRepeater.count
        for (let i = 0; i < n; ++i) {
            const w = root.windowsRepeater.objectAt(i)
            if (!w || !w.client || !w.client.active) continue
            if (w.stackedOnto || _hasStackMembers(w))
                promoteStackMember(w)
            return
        }
    }

    readonly property Connections _grabWatcher: Connections {
        target: root.xray
        function onGrabbedObjectChanged() {
            const now = root.xray.grabbedObject
            if (now) {
                root._dragStartedThisPress = true
                // Stacked member grabbed → detach immediately. Drag intent
                // implies "take this out of the stack". Snap-commit may
                // re-stack to a new target if user drops on one.
                if (now.stackedOnto)
                    root._detachFromStack(now)
                root._captureStackDrag(now)
            } else {
                console.log(Logger.kwinvr, "Snap release: target=", root.currentTarget,
                            "action=", root.actionName(root.currentAction))
                if (root._lastDragged
                    && root.currentTarget
                    && root.currentAction !== WindowSnapManager.Action.None) {
                    root._commitSnap(root._lastDragged, root.currentTarget, root.currentAction)
                }
                // Restore parent on members; their scene pose is preserved
                // (since they were children of grabbed throughout the drag,
                // including during _commitSnap's writes).
                root._releaseStackDrag()
                root._lastDragged = null
                root._setIntent(null, WindowSnapManager.Action.None)
            }
        }
    }

}
