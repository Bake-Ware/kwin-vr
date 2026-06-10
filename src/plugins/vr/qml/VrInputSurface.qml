/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>
    SPDX-FileCopyrightText: 2026 bake

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

import org.kde.kwin.vr

/*
 * The shared interaction grammar (see doc/VOCABULARY.md): mouse/key events →
 * workspace actions. Used verbatim by both the XR root (Main.qml) and the
 * flat-monitor root (MainFlat.qml) so the vocabulary stays input-identical
 * across renderers.
 */
MouseArea {
    id: mouseArea

    /* The VrWorkspaceScene all actions are routed to. */
    required property VrWorkspaceScene ws

    focus: true
    acceptedButtons: Qt.AllButtons

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

    /* Flat mode: middle-button drag emits lookDelta (camera steer). */
    property bool middleDragLook: false
    signal lookDelta(real dx, real dy)
    property real _lastLookX: 0
    property real _lastLookY: 0
    property bool _looking: false
    onPositionChanged: (event) => {
                           if (_looking) {
                               lookDelta(event.x - _lastLookX, event.y - _lastLookY)
                               _lastLookX = event.x
                               _lastLookY = event.y
                           }
                       }

    property bool desktopGrabbed: false
    /* Left-click empty-space grab-world: drag on motion, toggle on no-motion click */
    property bool worldGrabbing: false
    property real worldPressX: 0
    property real worldPressY: 0
    onPressed: (event) => {
                   if (middleDragLook && event.button === Qt.MiddleButton) {
                       _looking = true
                       _lastLookX = event.x
                       _lastLookY = event.y
                       return;
                   }

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
                    if (_looking && event.button === Qt.MiddleButton) {
                        _looking = false
                        return;
                    }

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

    /* Pinch-to-resize: track cumulative scale and apply per-update deltas */
    property var pinchFilter: null
    QtObject {
        id: pinchState
        property real lastScale: 1.0
    }
    Connections {
        target: mouseArea.pinchFilter
        ignoreUnknownSignals: true
        function onPinchStarted(fingerCount) {
            pinchState.lastScale = 1.0
        }
        function onPinchUpdated(scale, angleDelta) {
            // scale is cumulative from gesture start; compute incremental ratio
            if (pinchState.lastScale > 0.001) {
                const ratio = scale / pinchState.lastScale
                mouseArea.ws.pinchResizeGrabbed(ratio)
            }
            pinchState.lastScale = scale
        }
    }

    Connections {
        target: KWinVrShortcuts
        function onRealignWindowTriggered() { mouseArea.ws.realignItem() }
        function onGrabWindowTriggered() { mouseArea.ws.grab(false) }
        function onGrabAllWindowsTriggered() { mouseArea.ws.grab(true) }
        function onToggleHudTriggered() { mouseArea.ws.hudEnabled = !mouseArea.ws.hudEnabled }
        function onTestAction1Triggered() { mouseArea.ws.test1 = !mouseArea.ws.test1 }
        function onTestAction2Triggered() { mouseArea.ws.die() }
        function onToggleRayTriggered() { mouseArea.ws.rayEnabled = !mouseArea.ws.rayEnabled }
        function onToggleCursorTriggered() { mouseArea.ws.cursorEnabled = !mouseArea.ws.cursorEnabled }
        function onResetViewTriggered() { mouseArea.ws.resetView() }
    }
}
