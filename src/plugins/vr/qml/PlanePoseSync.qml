/*
    SPDX-FileCopyrightText: 2026 Bake-Ware

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
 * PlanePoseSync — singleton state bus for window-plane pose state across
 * Vr2DViewports.
 *
 * Two Vr2DViewport windows can't share their scene tree directly because
 * Qt's QQuickWindow architecture rejects cross-window QSGTexture sharing
 * (View3D.importScene logs "Cannot use QSGTexture ... created in another
 * window" and refuses to render the surface content textures in the
 * non-primary viewport). Each viewport therefore keeps its own scene
 * tree — own PlaneRegistry, own KwinApplicationWindow Repeater3D
 * delegates, own GL textures pulled from KWin SurfaceItem — and we sync
 * pose state through this singleton.
 *
 * Wire model:
 *   - Key = stringified `client.internalId` (KWin Window's stable ID).
 *   - Pose payload: scene-space `position` + `rotation` + curvature.
 *     Scene coords are the right channel: each viewport's WindowSceneRoot
 *     sits at (0,0,0) in its own View3D, so a scenePosition value
 *     transfers 1:1 across viewports. (intrinsicPosition lives in the
 *     plane's Qt parent's local frame and is not what gets mutated
 *     during a grab; mid-drag the source-of-truth is the Node's
 *     `position` which is parent-local — `scenePosition` is the live
 *     world-space derived value we can broadcast.)
 *   - `setPose(clientId, scenePos, sceneRot, curvature)` writes + bumps
 *     `revision` + sets `lastChangedClientId`.
 *   - `endGrab(clientId)` fires `grabEnded(clientId)`. Receivers reset
 *     `isGrabbed=false` so the abductor binding resumes (slot snap-back).
 *
 * Why isGrabbed needs toggling on receivers:
 *   Slotted planes (most app windows are children of a pseudo-mirror)
 *   compute their pose from `abductor.computeChild*(planeId)`. A direct
 *   write via `setNodePositionFromScene` is overwritten next frame
 *   unless the binding is suspended via `isGrabbed=true`. Receivers
 *   set it true on first incoming pose and false on `grabEnded`.
 *
 * Container-slotted state (slot list mutation, container creation /
 * dissolution) is NOT synced through this bus. Each viewport's
 * PlaneInteractionManager mutates its own local registry and the bus
 * only syncs the rendered pose. Cross-viewport container state is a
 * separate channel.
 */

pragma Singleton

import QtQuick

QtObject {
    id: root

    // clientId (string) → { scenePosition, sceneRotation, curvature }
    property var _poses: ({})

    // Monotonic counter bumped on every pose change. Listeners hang
    // their reactivity off this — QML's binding tracker doesn't fire
    // on per-key changes inside a `var` map.
    property int revision: 0

    // Last clientId whose pose changed. Listeners gate on equality so
    // each plane's listener only acts on its own change.
    property string lastChangedClientId: ""

    // Fired when a remote viewport's drag releases. Receivers clear
    // their own `isGrabbed` to let the local abductor binding take
    // over again (slot snap-back / dissolve).
    signal grabEnded(string clientId)

    function setPose(clientId, scenePosition, sceneRotation, curvature) {
        if (!clientId) return
        const id = "" + clientId
        _poses[id] = {
            scenePosition: scenePosition,
            sceneRotation: sceneRotation,
            curvature: curvature
        }
        lastChangedClientId = id
        revision = revision + 1
    }

    function getPose(clientId) {
        if (!clientId) return null
        return _poses["" + clientId] || null
    }

    function hasPose(clientId) {
        if (!clientId) return false
        return _poses.hasOwnProperty("" + clientId)
    }

    function endGrab(clientId) {
        if (!clientId) return
        grabEnded("" + clientId)
    }

    function clearPose(clientId) {
        if (!clientId) return
        const id = "" + clientId
        if (_poses.hasOwnProperty(id)) {
            delete _poses[id]
            lastChangedClientId = id
            revision = revision + 1
        }
    }
}
