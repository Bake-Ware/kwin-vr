// Copyright (C) 2023 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR BSD-3-Clause

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick3D.Helpers
import QtQuick3D

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
        headScroll: ws.headScroll
        inputDevice: kwinInput
    }

    // TODO: need to move all input related stuff to the better place
    MouseArea {
        id: mouseArea
        focus: true
        Keys.onPressed: (event) => {
                            ws.closeRadialMenu();

                            if(ws.grabbed) {
                                if(event.key === Qt.Key_Up) {
                                    ws.pushGrabbed = true
                                    event.accepted = true
                                } else if(event.key === Qt.Key_Down) {
                                    ws.pullGrabbed = true
                                    event.accepted = true
                                }
                            }
                        }
        Keys.onReleased: (event) => {
                             if(ws.grabbed) {
                                 if(event.key === Qt.Key_Up) {
                                     ws.pushGrabbed = false
                                     event.accepted = true
                                 } else if(event.key === Qt.Key_Down) {
                                     ws.pullGrabbed = false
                                     event.accepted = true
                                 }
                             }
                         }


        acceptedButtons: Qt.AllButtons

        property bool desktopGrabbed: false
        /* Left-click empty-space grab-world: drag on motion, toggle on no-motion click */
        property bool worldGrabbing: false
        property real worldPressX: 0
        property real worldPressY: 0
        onPressed: (event) => {
                       const wasWorldLatched = ws.worldGrabbed
                       /* Release grabbed object on any button press */
                       if(ws.release()) {
                           if(wasWorldLatched) {
                               /* Latch release — if clicked a window, let it through */
                               if(ws.cursorHoverObject) {
                                   event.accepted = false
                               }
                               return;
                           }
                            /* Nedd to send key press further for kwin to release thw window */
                           if(ws.currentMovingResizingWindow) {
                               event.accepted = false
                           }
                           return;
                       }

                       if(event.modifiers & Qt.MetaModifier) {
                           desktopGrabbed = ws.grabDesktop()
                           if(desktopGrabbed) {
                               return;
                           }
                       }

                       if(!ws.cursorHoverObject) {
                           if(event.button === Qt.LeftButton) {
                               /* Begin grab immediately; release decides drag vs latch */
                               worldGrabbing = true
                               worldPressX = event.x
                               worldPressY = event.y
                               ws.grab(true)
                               return;
                           }
                           if(event.button === Qt.RightButton) {
                               if(ws.radialMenuActivate(true)) {
                                   return;
                               }
                           }
                       }

                       event.accepted = false
                   }
        onReleased: (event) => {
                        if(desktopGrabbed) {
                            ws.grab(false)
                            desktopGrabbed = false
                            return;
                        }

                        if(worldGrabbing) {
                            const moved = (event.x !== worldPressX) || (event.y !== worldPressY)
                            if(moved) {
                                ws.release()
                            }
                            worldGrabbing = false
                            return;
                        }

                        if(event.button === Qt.RightButton && !ws.cursorHoverObject) {
                            if(ws.radialMenuActivate(false)) {
                                return;
                            }
                        }
                    }
        onWheel: (event) => {
                     const dy = event.angleDelta.y
                     if (dy === 0)
                         return
                     const direction = dy > 0 ? 1.0 : -1.0
                     const step = direction * KWinVRConfig.grabResizeSensitivity
                     if (event.modifiers & Qt.ShiftModifier) {
                         ws.resizeGrabbed(step, 0)
                     } else if (event.modifiers & Qt.ControlModifier) {
                         ws.resizeGrabbed(0, step)
                     } else {
                         ws.scrollGrab(dy)
                     }
                 }
    }

    XrScene {
        id: xrView
        kwinInput: kwinInput
        kwinInputFilter: kwinInputFIlter
    }

    /* The renderer-agnostic workspace — all interaction goes through this,
       never through the scene root, so flat/XR scene roots stay swappable. */
    readonly property VrWorkspaceScene ws: xrView.workspace

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
                ws.pinchResizeGrabbed(ratio)
            }
            pinchState.lastScale = scale
        }
    }

    Connections {
        target: KWinVrShortcuts
        function onRealignWindowTriggered() { ws.realignItem() }
        function onGrabWindowTriggered() { ws.grab(false) }
        function onGrabAllWindowsTriggered() { ws.grab(true) }
        function onToggleHudTriggered() { ws.hudEnabled = !ws.hudEnabled }
        function onTestAction1Triggered() { ws.test1 = !ws.test1 }
        function onTestAction2Triggered() { ws.die() }
        function onToggleRayTriggered() { ws.rayEnabled = !ws.rayEnabled }
        function onToggleCursorTriggered() { ws.cursorEnabled = !ws.cursorEnabled }
        function onResetViewTriggered() { ws.resetView() }
    }
}
