/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
 * WindowSnapManager — Step 1 of natural-drag dock + stack (#14).
 *
 * Scans for snap/stack intent each frame while a VR-floating window is grabbed.
 * Logs detected intent on change. No visual telegraph, no commit, no resize yet.
 *
 * Quad model: each window has 4 quads (TL/TR/BL/BR) in its local 2D plane.
 * Per dragged-quad center inside target rect → matched to one of target's quads.
 * Same-side match (e.g. dragged-LEFT ↔ target-LEFT) → stack vote.
 * Opposite-side match (e.g. dragged-LEFT ↔ target-RIGHT) → snap vote that direction.
 * Combined participating quad count must be ≥3 to fire intent (rejects diagonal corners).
 * Highest vote wins; ties break in favor of snap over stack.
 */

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

QtObject {
    id: root

    enum Action { None, SnapLeft, SnapRight, SnapAbove, SnapBelow, Stack }

    required property Xray xray
    required property var windowsRepeater   // applicationWindowsRepeater

    // Reject candidates whose plane is more than this far from dragged center.
    // Keeps depth-aligned but distance-separated windows from cross-triggering.
    property real maxPlaneDistance: 1.0

    property Node currentTarget: null
    property int currentAction: WindowSnapManager.Action.None

    // Landing pose for the telegraph ghost (#14 step 2).
    // landingLocalOffset is in currentTarget's local frame; consumer maps to scene/parent.
    // landingSize is in world units (width × height).
    property vector3d landingLocalOffset: Qt.vector3d(0, 0, 0)
    property size landingSize: Qt.size(0, 0)

    // Tracks last grabbed object so we can detect release and commit snap.
    property var _lastDragged: null

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

    // Compute landing pose for current intent. Position is in target-local 2D.
    function _computeLanding() {
        const t = currentTarget
        const a = currentAction
        if (!t || !t.client || a === WindowSnapManager.Action.None) {
            landingLocalOffset = Qt.vector3d(0, 0, 0)
            landingSize = Qt.size(0, 0)
            return
        }
        const dragged = xray.grabbedObject as KwinApplicationWindow
        if (!dragged || !dragged.client) {
            landingLocalOffset = Qt.vector3d(0, 0, 0)
            landingSize = Qt.size(0, 0)
            return
        }
        const tg = t.client.frameGeometry
        const dg = dragged.client.frameGeometry
        const tw = tg.width / t.ppu, th = tg.height / t.ppu
        const dw = dg.width / dragged.ppu, dh = dg.height / dragged.ppu

        let off = Qt.vector3d(0, 0, 0)
        let sz = Qt.size(0, 0)
        switch (a) {
        case WindowSnapManager.Action.Stack:
            off = Qt.vector3d(0, 0, 0)
            sz = Qt.size(tw, th)
            break
        case WindowSnapManager.Action.SnapRight:
            off = Qt.vector3d(tw / 2 + dw / 2, 0, 0)
            sz = Qt.size(dw, th)
            break
        case WindowSnapManager.Action.SnapLeft:
            off = Qt.vector3d(-(tw / 2 + dw / 2), 0, 0)
            sz = Qt.size(dw, th)
            break
        case WindowSnapManager.Action.SnapAbove:
            off = Qt.vector3d(0, th / 2 + dh / 2, 0)
            sz = Qt.size(tw, dh)
            break
        case WindowSnapManager.Action.SnapBelow:
            off = Qt.vector3d(0, -(th / 2 + dh / 2), 0)
            sz = Qt.size(tw, dh)
            break
        }
        landingLocalOffset = off
        landingSize = sz
    }

    // Compute snap intent via 2D overlap rect + centroid bias in target local plane.
    // Quads are still the conceptual model (user spec) but execution uses overlap math
    // so detection works regardless of drag-approach direction.
    // Returns { action: Action }.
    function _evaluatePair(dragged, target) {
        const tg = target.client.frameGeometry
        const dg = dragged.client.frameGeometry
        if (tg.width <= 0 || tg.height <= 0 || dg.width <= 0 || dg.height <= 0)
            return { action: WindowSnapManager.Action.None }

        const tw = tg.width / target.ppu
        const th = tg.height / target.ppu
        const dw = dg.width / dragged.ppu
        const dh = dg.height / dragged.ppu

        // Plane-distance gate: dragged center far from target's plane → reject.
        const dCenterInTarget = target.mapPositionFromScene(dragged.scenePosition)
        if (Math.abs(dCenterInTarget.z) > maxPlaneDistance)
            return { action: WindowSnapManager.Action.None }

        // Project dragged's 4 corners into target local 2D, bound by min/max.
        const corners = [
            Qt.vector3d(-dw / 2, +dh / 2, 0),
            Qt.vector3d(+dw / 2, +dh / 2, 0),
            Qt.vector3d(-dw / 2, -dh / 2, 0),
            Qt.vector3d(+dw / 2, -dh / 2, 0)
        ]
        let minX = Number.POSITIVE_INFINITY, maxX = Number.NEGATIVE_INFINITY
        let minY = Number.POSITIVE_INFINITY, maxY = Number.NEGATIVE_INFINITY
        for (const c of corners) {
            const local = target.mapPositionFromScene(dragged.mapPositionToScene(c))
            if (local.x < minX) minX = local.x
            if (local.x > maxX) maxX = local.x
            if (local.y < minY) minY = local.y
            if (local.y > maxY) maxY = local.y
        }

        // Intersect with target rect [-tw/2, tw/2] × [-th/2, th/2].
        const oMinX = Math.max(minX, -tw / 2)
        const oMaxX = Math.min(maxX, +tw / 2)
        const oMinY = Math.max(minY, -th / 2)
        const oMaxY = Math.min(maxY, +th / 2)
        if (oMaxX <= oMinX || oMaxY <= oMinY)
            return { action: WindowSnapManager.Action.None }

        // Reject diagonal-corner barely-touching overlap (user's no-op rule).
        const overlapArea = (oMaxX - oMinX) * (oMaxY - oMinY)
        const minWindowArea = Math.min(tw * th, dw * dh)
        if (overlapArea / minWindowArea < 0.05)
            return { action: WindowSnapManager.Action.None }

        // Centroid bias in normalized target coords (-1..+1).
        const cx = (oMinX + oMaxX) / 2
        const cy = (oMinY + oMaxY) / 2
        const xBias = cx / (tw / 2)
        const yBias = cy / (th / 2)

        // Stack zone: centroid within central 40% on both axes.
        const stackThreshold = 0.4
        if (Math.abs(xBias) < stackThreshold && Math.abs(yBias) < stackThreshold)
            return { action: WindowSnapManager.Action.Stack }

        // Snap: dominant-axis bias picks side. xBias > 0 means overlap is on
        // target's RIGHT side, which means dragged is to the RIGHT of target → SnapRight.
        if (Math.abs(xBias) >= Math.abs(yBias))
            return { action: xBias > 0 ? WindowSnapManager.Action.SnapRight
                                       : WindowSnapManager.Action.SnapLeft }
        return { action: yBias > 0 ? WindowSnapManager.Action.SnapAbove
                                   : WindowSnapManager.Action.SnapBelow }
    }

    function _scan() {
        const dragged = xray.grabbedObject as KwinApplicationWindow
        if (!dragged || !dragged.client || !dragged.client.vr) {
            _setIntent(null, WindowSnapManager.Action.None)
            return
        }
        _lastDragged = dragged

        let bestTarget = null
        let bestAction = WindowSnapManager.Action.None
        let bestDist = Number.POSITIVE_INFINITY
        const draggedScene = dragged.scenePosition

        for (let i = 0; i < windowsRepeater.count; ++i) {
            const cand = windowsRepeater.objectAt(i) as KwinApplicationWindow
            if (!cand || cand === dragged) continue
            if (!cand.client || !cand.client.vr) continue

            const result = _evaluatePair(dragged, cand)
            if (result.action === WindowSnapManager.Action.None) continue

            const d = cand.scenePosition.minus(draggedScene).length()
            if (d < bestDist) {
                bestDist = d
                bestTarget = cand
                bestAction = result.action
            }
        }

        _setIntent(bestTarget, bestAction)

        // Z-only depth clamp during drag: dragged lays on target's plane like
        // a pseudomirror surface. Lateral X/Y stay ray-driven so scan sees the
        // same overlap each frame (no oscillation). Only fires when dragged
        // would penetrate or pass behind target plane.
        if (bestTarget && bestAction !== WindowSnapManager.Action.None) {
            const zFwd = KWinVRConfig.zSurfaceMarginTop / 100.0
            const localCenter = bestTarget.mapPositionFromScene(dragged.scenePosition)
            if (localCenter.z < zFwd) {
                const stuckLocal = Qt.vector3d(localCenter.x, localCenter.y, zFwd)
                KwinVrHelpers.setNodePositionFromScene(dragged, bestTarget.mapPositionToScene(stuckLocal))
            }
        }
    }

    // Apply the snap on release: resize + reposition + rotation align.
    function _commitSnap(dragged, target, action) {
        if (!dragged || !target || !dragged.client || !target.client) return

        const tg = target.client.frameGeometry
        const dg = dragged.client.frameGeometry
        const tw = tg.width / target.ppu, th = tg.height / target.ppu
        const dw = dg.width / dragged.ppu, dh = dg.height / dragged.ppu

        // Forward Z offset reuses the pseudomirror surface-stacking margin.
        // kcfg stores it in cm; divide by 100 to use as scene-space metres.
        const zFwd = KWinVRConfig.zSurfaceMarginTop / 100.0

        let localOffset = Qt.vector3d(0, 0, zFwd)
        let landW = 0, landH = 0
        switch (action) {
        case WindowSnapManager.Action.Stack:
            landW = tw; landH = th
            break
        case WindowSnapManager.Action.SnapRight:
            localOffset = Qt.vector3d(tw / 2 + dw / 2, 0, zFwd)
            landW = dw; landH = th
            break
        case WindowSnapManager.Action.SnapLeft:
            localOffset = Qt.vector3d(-(tw / 2 + dw / 2), 0, zFwd)
            landW = dw; landH = th
            break
        case WindowSnapManager.Action.SnapAbove:
            localOffset = Qt.vector3d(0, th / 2 + dh / 2, zFwd)
            landW = tw; landH = dh
            break
        case WindowSnapManager.Action.SnapBelow:
            localOffset = Qt.vector3d(0, -(th / 2 + dh / 2), zFwd)
            landW = tw; landH = dh
            break
        }

        // Capture pre-snap geometry the first time this window snaps. Future
        // detach restores from this. Stored as JS dynamic property.
        if (!dragged.preSnapGeom)
            dragged.preSnapGeom = Qt.size(dg.width, dg.height)

        // Resize via KWin (delta in px). Async — surface acks later.
        const dw_px = landW * target.ppu - dg.width
        const dh_px = landH * target.ppu - dg.height
        if (Math.abs(dw_px) > 0.5 || Math.abs(dh_px) > 0.5)
            KwinVrHelpers.windowResize(dragged.client, dw_px, dh_px)

        // Position + rotation match target's plane.
        const landScene = target.mapPositionToScene(localOffset)
        KwinVrHelpers.setNodePositionFromScene(dragged, landScene)
        KwinVrHelpers.setNodeRotationFromScene(dragged, target.sceneRotation)

        const tklass = target.client.resourceClass || "?"
        console.log(Logger.kwinvr, "Snap commit:", actionName(action), "→", tklass,
                    "preSnap:", dragged.preSnapGeom)
    }

    // Per-frame scan triggered by ray pose changes while something is grabbed.
    readonly property Connections _scanWatcher: Connections {
        target: root.xray
        enabled: root.xray && root.xray.grabbedObject !== null
        function onSceneTransformChanged() { root._scan() }
    }

    // On release: commit pending snap (if intent was locked) then clear intent.
    readonly property Connections _grabWatcher: Connections {
        target: root.xray
        function onGrabbedObjectChanged() {
            const now = root.xray.grabbedObject
            if (!now) {
                console.log(Logger.kwinvr, "Snap release: lastDragged=", root._lastDragged,
                            "target=", root.currentTarget, "action=", root.actionName(root.currentAction))
                if (root._lastDragged
                    && root.currentTarget
                    && root.currentAction !== WindowSnapManager.Action.None) {
                    root._commitSnap(root._lastDragged, root.currentTarget, root.currentAction)
                }
                root._lastDragged = null
                root._setIntent(null, WindowSnapManager.Action.None)
            }
        }
    }
}
