/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

/*
 * VrWindowManipulation - Handles window moving windows to and out of VR
 */

import QtQuick
import QtQuick3D
import QtQuick3D.Xr

import org.kde.kwin as KWinC
import org.kde.kwin.vr

QtObject {
    id: root

    required property KwinVrInputDevice kwinInput
    required property VrHeadScroll headScroll
    required property Xray xray
    required property VrPicking picking
    required property VrPointerHandler pointerHandler

    // Margin in pixels before a window detaches from screen to VR (0 = immediate)
    property int windowDetachMargin: 80

    // Normalized Y inverted cursor position at the start of a move operation (for fullscreen windows)
    property point moveStartCursorPosNormalized: Qt.point(0, 0)

    // Convenience alias to the moving/resizing window (owned by pointerHandler)
    readonly property Node currentMovingResizingWindow: pointerHandler.currentMovingResizingWindow

    // Keeps initial maximization mode when we started moving a window
    property int maximizationMode: 0

    readonly property VrBarrierConstraint barrierConstraint: VrBarrierConstraint {
        bounds: root.currentMovingResizingWindow?.client?.output?.geometry ?? Qt.rect(0, 0, 0, 0)
        margin: root.windowDetachMargin
        enabled: root.barrierEnabled
        onBeyondMargin: root.detachWindowToVR()
    }

    // Barrier is active only for non-VR windows being moved
    readonly property bool barrierEnabled: {
        const window = root.currentMovingResizingWindow?.client
        if (!window)
            return false
        return !window.vr && !root.xray.grabbedObject && window.move
    }

    // Attach/detach constraint to pointer handler
    readonly property Binding constraintBinding: Binding {
        target: root.pointerHandler
        property: "constraint"
        value: root.barrierConstraint
        when: root.barrierEnabled
    }

    readonly property Connections movingResizingWindowWatcher: Connections {
        target: root.pointerHandler
        function onCurrentMovingResizingWindowChanged(): void {
            const window = root.currentMovingResizingWindow?.client
            if (window && window.move && !window.transientFor) {
                root.moveStartCursorPosNormalized = root.rectPointToUnit(window.frameGeometry, KWinC.Workspace.cursorPos)
                root.maximizationMode = window.maximizeMode

                if (window.vr) { // Moving VR window
                    const appWin = root.currentMovingResizingWindow.grabHandle as KwinApplicationWindow
                    // Grab the CurvedPlane sibling, not the (invisible) flat
                    // KwinApplicationWindow Node — that's the entity registered
                    // in PlaneRegistry and the one PlaneInteractionManager
                    // expects to see in xray.grabbedObject.
                    const target = (appWin && appWin.vrPlane) ? appWin.vrPlane : appWin
                    if(!target || root.xray.grabbedObject === target) {
                        return
                    }

                    if (root.xray.grabbedObject) {
                        root.xray.release()
                    }

                    root.xray.grabAndAlign(target)

                    // Movement of the window might begin from a hotkey press or
                    // context menu — align manually to the ray-cursor.
                    root.alignGrabbedWindowToRayAtCursor(target, KWinC.Workspace.cursorPos)
                }
            } else {
                if (!root.currentMovingResizingWindow) {
                    root.xray.release()
                }
            }
        }
    }

    function isWindowUnderRay(appWin): bool {
        return root.picking.isGrabHandlePicked(appWin)
    }

    function isPointInRect(point: point, rect: rect): bool {
        return point.x >= rect.x &&
               point.x <= rect.x + rect.width &&
               point.y >= rect.y &&
               point.y <= rect.y + rect.height
    }

    function get3DCursorPos(target, cursorPos: point): var {
        let ret = {
            result: false,
            position: Qt.vector3d(0, 0, 0)
        }
        // target may be a KwinApplicationWindow (legacy) or a CurvedPlane.
        // Both expose .content/.client + mapPositionToScene + ppu.
        const window = target ? (target.content ?? target.client) : null
        if (!window) {
            return ret
        }

        const geom = window.frameGeometry
        const inside = isPointInRect(cursorPos, geom)
        if (!inside) {
            return ret
        }

        const fixedCursorPos = (cursorPos.x === geom.x && cursorPos.y === geom.bottom) ?
                                 Qt.point(geom.x + geom.width / 2, geom.y + geom.height / 2) :
                                 cursorPos

        const localOffset = Qt.vector3d(
            (fixedCursorPos.x - (geom.x + geom.width / 2)) / target.ppu,
            -(fixedCursorPos.y - (geom.y + geom.height / 2)) / target.ppu,
            0
        )

        ret.position = target.mapPositionToScene(localOffset)
        ret.result = true
        return ret
    }

    // Returning 0.5 here to align the ray to the window center in case of the cursor is outside of the window
    function rectPointToUnit(geom: rect, pointerPos: point): point {
        if (geom.width <= 0 || geom.height <= 0) {
            return Qt.point(0.5, 0.5)
        }

        const inside = isPointInRect(pointerPos, geom)
        if (!inside) {
            return Qt.point(0.5, 0.5)
        }

        return Qt.point(
            (pointerPos.x - geom.x) / geom.width,
            (geom.y + geom.height - pointerPos.y) / geom.height
        )
    }

    function unitToRectPoint(geom: rect, normalizedPos: point): point {
        return Qt.point(
            geom.x + normalizedPos.x * geom.width,
            geom.y + (1 - normalizedPos.y) * geom.height
        )
    }

    function alignGrabbedWindowToRayAtCursor(target, cursorPos: point): void {
        root.xray.applyGrab()

        const ret = root.get3DCursorPos(target, cursorPos);
        if(!ret.result) {
            console.log(Logger.kwinvr, "Can't get 3d coordinates of a pointer inside window", target, cursorPos)
            root.xray.alignGrabbedObjectToCamera()
            return;
        }

        if(!root.xray.rotateGrabbedObjectAroundCameraToRay(root.xray, ret.position)) {
            root.xray.alignGrabbedObjectToCamera()
            return;
        }
    }

    function rayPickPseudoOutput(): var {
        const allPicks = root.picking.lastAllPicks
        for(var pickResult of allPicks) {
            const obj = pickResult.objectHit ?? root.picking.getHoveredNodeFromItem(pickResult.itemHit)
            if(!obj) {
                continue
            }

            const pseudoOutput = (obj as VrScreenFrame)?.parent as KwinPseudoOutputMirror
            if (pseudoOutput) {
                return {
                    pseudoOutput: pseudoOutput,
                    pick: pickResult
                }
            }
        }
        return null
    }

    function detachWindowToVR(): void {
        const appWin =  root.currentMovingResizingWindow?.parent?.parent as KwinApplicationWindow
        if (!appWin)
            return

        const window = appWin.client
        if (!window)
            return

        const outputGeo = window.output.geometry

        const ret = root.rayPickPseudoOutput()
        if (ret && ret.pseudoOutput.output === window.output) {
            return
        }

        // Grab the CurvedPlane sibling; it's what's registered with the
        // PlaneInteractionManager and the current rendering target.
        const target = appWin.vrPlane ?? appWin
        xray.grabAndAlign(target)
        const cursorPos = window.fullScreen ? root.unitToRectPoint(window.frameGeometry, root.moveStartCursorPosNormalized) : KWinC.Workspace.cursorPos
        root.alignGrabbedWindowToRayAtCursor(target, cursorPos)
        window.vr = true

        // Wayland apps do not need this, since they know nothing about the screen geometry.
        // X11 apps need this for better placement of menus and other popups.
        KwinVrHelpers.windowMove(window, Qt.point(outputGeo.x, outputGeo.y))

        // Maybe this is kinda strange, but it improves usability
        // Moving maximized window restores its geometry, but when you pull a window out of the screen,
        // it feels that it needed to be maximized again.
        if (root.maximizationMode) {
            window.setMaximize((root.maximizationMode & 1), (root.maximizationMode & 2))
        }
    }

    // Resolves the KWin client from either currentMovingResizingWindow or the
    // grabbed object. Handles legacy KwinApplicationWindow grabs as well as
    // CurvedPlane grabs (where .content holds the client).
    function resolveGrabbedClient(): QtObject {
        if (root.currentMovingResizingWindow)
            return root.currentMovingResizingWindow.client ?? null

        const obj = root.xray.grabbedObject
        if (!obj) return null
        return obj.content ?? obj.client ?? null
    }

    readonly property Connections lookForScreenToPut: Connections {
        target: root.picking
        enabled: xray.grabbedObject !== null
        function onLastAllPicksChanged(): void {
            const window = root.resolveGrabbedClient()
            if (!window || !window.vr) {
                return
            }

            const ret = root.rayPickPseudoOutput()
            if (!ret) {
                return
            }

            const pseudoOutput = ret.pseudoOutput
            const pick = ret.pick

            // We need to move pointer in 2D world where we will land our window
            root.kwinInput.pointerPosition = pseudoOutput.uvToGlobal2DCoordinates(pick.uvPosition)

            KWinC.Workspace.sendClientToScreen(window, pseudoOutput.output)

            xray.release()
            window.vr = false
        }
    }
}
