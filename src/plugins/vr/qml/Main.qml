// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick3D.Helpers
//! [XrView]
import QtQuick3D
import QtQuick3D.Xr

import org.kde.kwin as KWinC
import org.kde.kwin.vr

Item {
    id: root

    KwinVrInputDevice {
        id: kwinInput
        active: true
    }

    KwinVrInputFilter {
        id: kwinInputFIlter
        eventsTarget: mouseArea
        pointerInhibitDelay: KWinVRConfig.pointerInhibitDelay
    }

    KwinInputRemap {
        inputDevice: kwinInput
    }

    VrHeadScrollFilter {
        headScroll: xrView.headScroll
        inputDevice: kwinInput
    }

    // TODO: need to move all input related stuff to the better place
    MouseArea {
        id: mouseArea
        focus: true
        Keys.onPressed: (event) => {
                            xrView.closeRadialMenu();

                            if(xrView.grabbed) {
                                if(event.key === Qt.Key_Up) {
                                    xrView.pushGrabbed = true
                                    event.accepted = true
                                } else if(event.key === Qt.Key_Down) {
                                    xrView.pullGrabbed = true
                                    event.accepted = true
                                }
                            }
                        }
        Keys.onReleased: (event) => {
                             if(xrView.grabbed) {
                                 if(event.key === Qt.Key_Up) {
                                     xrView.pushGrabbed = false
                                     event.accepted = true
                                 } else if(event.key === Qt.Key_Down) {
                                     xrView.pullGrabbed = false
                                     event.accepted = true
                                 }
                             }
                         }


        acceptedButtons: Qt.AllButtons

        property bool desktopGrabbed: false
        property bool emptySpaceGrabbed: false
        // Latch that makes the empty-space world-grab persist past button
        // release. Set by a double-click on empty space; cleared by any
        // subsequent press. Lets the user "pin" the world while they walk
        // around / watch a floating video without holding the mouse.
        property bool emptySpaceGrabToggled: false
        property bool bothClicked: false
        property bool gizmoDragActive: false
        property int heldButtons: 0
        property real lastLeftPressMs: 0
        property real lastRightPressMs: 0
        onPressed: (event) => {
                       mouseArea.heldButtons |= event.button
                       const nowMs = Date.now()
                       const prevLeftPressMs = mouseArea.lastLeftPressMs
                       if (event.button === Qt.LeftButton) mouseArea.lastLeftPressMs = nowMs
                       else if (event.button === Qt.RightButton) mouseArea.lastRightPressMs = nowMs

                       /* Toggle-grab is active: any press drops it and consumes
                        * the click (no new grab / menu / selection). */
                       if (emptySpaceGrabToggled) {
                           xrView.release()
                           emptySpaceGrabToggled = false
                           emptySpaceGrabbed = false
                           return;
                       }

                       /* Super+Click = select/deselect object (gizmo) */
                       if (event.modifiers & Qt.MetaModifier && !(event.modifiers & Qt.ControlModifier)) {
                           xrView.selectObjectAtCursor()
                           bothClicked = true
                           return;
                       }

                       /* Double-click on empty space = toggle world grab.
                        * Reuse grabAllIfEmptySpace() which handles the empty-
                        * space conditions and the grab itself; we just latch
                        * the toggle flag on top. Checked BEFORE both-click
                        * radial so rapid VR-trigger double taps that emit L+R
                        * together don't fall into the menu path. */
                       if (event.button === Qt.LeftButton
                           && (nowMs - prevLeftPressMs) < 300
                           && xrView.grabAllIfEmptySpace()) {
                           emptySpaceGrabbed = true
                           emptySpaceGrabToggled = true
                           return;
                       }

                       /* Both-click detection: L+R held within 400ms → open radial menu */
                       if ((mouseArea.heldButtons & Qt.LeftButton)
                           && (mouseArea.heldButtons & Qt.RightButton)
                           && Math.abs(mouseArea.lastLeftPressMs - mouseArea.lastRightPressMs) < 400) {
                           if (emptySpaceGrabbed || desktopGrabbed) {
                               xrView.release()
                               emptySpaceGrabbed = false
                               desktopGrabbed = false
                           }
                           bothClicked = true
                           xrView.openRadialMenuAtCursor()
                           return;
                       }

                       /* Release grabbed object on any button press */
                       if(xrView.release()) {
                            /* Nedd to send key press further for kwin to release thw window */
                           if(xrView.currentMovingResizingWindow) {
                               event.accepted = false
                           }
                           emptySpaceGrabbed = false
                           return;
                       }

                       /* Gizmo handle click — highest priority when gizmo is visible */
                       if (xrView.tryGizmoHandlePress()) {
                           gizmoDragActive = true
                           return;
                       }

                       if(event.modifiers & Qt.MetaModifier) {
                           desktopGrabbed = xrView.grabDesktop()
                           if(desktopGrabbed) {
                               return;
                           }
                       }

                       /* Left-click+hold on empty space = grab all */
                       if(event.button === Qt.LeftButton && xrView.grabAllIfEmptySpace()) {
                           emptySpaceGrabbed = true
                           return;
                       }

                       /* Activate/close radial menu if click on a hovered object */
                       if(xrView.radialMenuActivate(true)) {
                           return;
                       }

                       event.accepted = false
                   }
        onReleased: (event) => {
                        mouseArea.heldButtons &= ~event.button

                        /* Empty-space grab: drop on LeftButton release unless
                         * the grab is toggle-latched (double-click). Hoisted
                         * above bothClicked / gizmoDragActive so a stale flag
                         * can't leave the grab stuck. */
                        if (event.button === Qt.LeftButton
                            && emptySpaceGrabbed
                            && !emptySpaceGrabToggled) {
                            xrView.release()
                            emptySpaceGrabbed = false
                            if (mouseArea.heldButtons === 0)
                                bothClicked = false
                            return;
                        }

                        /* Toggle-grab latched: consume the release so the
                         * fall-through to radialMenuActivate(false) can't open
                         * the radial menu under the toggled world. */
                        if (emptySpaceGrabToggled) {
                            return;
                        }

                        /* Gizmo drag end first — never let bothClicked swallow it
                         * (VR pipeline can drop releases leaving bothClicked stale) */
                        if (gizmoDragActive) {
                            xrView.endGizmoDrag()
                            gizmoDragActive = false
                            if (mouseArea.heldButtons === 0)
                                bothClicked = false
                            return;
                        }

                        if (bothClicked) {
                            if (mouseArea.heldButtons === 0)
                                bothClicked = false
                            return;
                        }

                        if(desktopGrabbed) {
                            xrView.grab(false)
                            desktopGrabbed = false
                            return;
                        }

                        if(xrView.radialMenuActivate(false)) {
                            return;
                        }
                    }
        onWheel: (event) => {
                     const dy = event.angleDelta.y
                     if (dy === 0)
                         return
                     const direction = dy > 0 ? 1.0 : -1.0
                     const step = direction * KWinVRConfig.grabResizeSensitivity
                     if (event.modifiers & Qt.ShiftModifier) {
                         xrView.resizeGrabbed(step, 0)
                     } else if (event.modifiers & Qt.ControlModifier) {
                         xrView.resizeGrabbed(0, step)
                     } else {
                         xrView.scrollGrab(dy)
                     }
                 }
    }

    XrScene {
        id: xrView
        kwinInput: kwinInput
        kwinInputFilter: kwinInputFIlter
    }

    // Pinch-to-resize: track cumulative scale and apply per-update deltas
    QtObject {
        id: pinchState
        property real lastScale: 1.0
    }
    Connections {
        target: kwinInputFIlter
        function onPinchStarted(fingerCount) {
            pinchState.lastScale = 1.0
        }
        function onPinchUpdated(scale, angleDelta) {
            // scale is cumulative from gesture start; compute incremental ratio
            if (pinchState.lastScale > 0.001) {
                const ratio = scale / pinchState.lastScale
                xrView.pinchResizeGrabbed(ratio)
            }
            pinchState.lastScale = scale
        }
    }

    Connections {
        target: KWinVrShortcuts
        function onRealignWindowTriggered() { xrView.realignItem() }
        function onGrabWindowTriggered() { xrView.grab(false) }
        function onGrabAllWindowsTriggered() { xrView.grab(true) }
        function onToggleHudTriggered() { xrView.hudEnabled = !xrView.hudEnabled }
        function onTestAction1Triggered() { xrView.test1 = !xrView.test1 }
        function onTestAction2Triggered() { xrView.die() }
        function onToggleRayTriggered() { xrView.rayEnabled = !xrView.rayEnabled }
        function onToggleCursorTriggered() { xrView.cursorEnabled = !xrView.cursorEnabled }
        function onResetViewTriggered() { xrView.resetView() }
    }
}
