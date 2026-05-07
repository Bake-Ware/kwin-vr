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

    // KwinVrBridge.fallbackMode picks which viewport owns input + camera
    // at startup. Each viewport hosts its own scene tree (XrView is a
    // QQuick3DNode, can't importScene a shared root).
    //
    // VR mode is gated via Loader (XrScene is an Item subtree).
    // 2D fallback is a top-level Window, instantiated unconditionally
    // and gated via `visible` — Loader can't host Window.
    Loader {
        anchors.fill: parent
        active: !KwinVrBridge.fallbackMode
        sourceComponent: vrModeComponent
    }

    // Vr2DViewport is a top-level Window and Loader can't host one.
    // Spawn imperatively when fallbackMode is true. This also avoids the
    // Window-inside-Item binding-eval timing quirk that left `visible`
    // stuck at false when bound directly.
    property var _fallbackViewport: null

    function _maybeSpawnFallback() {
        if (KwinVrBridge.fallbackMode && !_fallbackViewport) {
            const comp = Qt.createComponent("Vr2DViewport.qml")
            if (comp.status === Component.Ready) {
                // Top-level Window: no QML parent. Call .show() explicitly
                // so the QQuickWindow registers as a kwin internal client.
                _fallbackViewport = comp.createObject(null)
                if (_fallbackViewport) {
                    _fallbackViewport.show()
                    console.warn("KWINVR Vr2DViewport spawned visible=", _fallbackViewport.visible,
                                 "size=", _fallbackViewport.width, "x", _fallbackViewport.height)
                } else {
                    console.warn("KWINVR Vr2DViewport createObject returned null")
                }
            } else {
                console.warn("KWINVR Vr2DViewport component error:", comp.errorString())
            }
        } else if (!KwinVrBridge.fallbackMode && _fallbackViewport) {
            _fallbackViewport.destroy()
            _fallbackViewport = null
        }
    }

    Connections {
        target: KwinVrBridge
        function onFallbackModeChanged() { root._maybeSpawnFallback() }
    }

    Component.onCompleted: {
        console.warn("KWINVR Main.qml ready, fallbackMode=", KwinVrBridge.fallbackMode)
        _maybeSpawnFallback()
    }

    Component {
        id: vrModeComponent
        Item {
            id: vrMode
            anchors.fill: parent

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
                /* Left-click empty-space grab-world: drag on motion, toggle on no-motion click */
                property bool worldGrabbing: false
                property real worldPressX: 0
                property real worldPressY: 0
                onPressed: (event) => {
                               /* Snapshot modifier state for downstream consumers.
                                * Qt.application.keyboardModifiers is unreliable in the
                                * VR overlay because the scene doesn't hold global
                                * keyboard focus; event.modifiers comes from the
                                * synthesized QMouseEvent and is accurate at press time. */
                               xrView.shiftHeldOnPress = !!(event.modifiers & Qt.ShiftModifier)

                               const wasWorldLatched = xrView.worldGrabbed
                               /* Release grabbed object on any button press */
                               if(xrView.release()) {
                                   if(wasWorldLatched) {
                                       /* Latch release — if clicked a window, let it through */
                                       if(xrView.cursorHoverObject) {
                                           event.accepted = false
                                       }
                                       return;
                                   }
                                    /* Nedd to send key press further for kwin to release thw window */
                                   if(xrView.currentMovingResizingWindow) {
                                       event.accepted = false
                                   }
                                   return;
                               }

                               if(event.modifiers & Qt.MetaModifier) {
                                   desktopGrabbed = xrView.grabDesktop()
                                   if(desktopGrabbed) {
                                       return;
                                   }
                               }

                               if(!xrView.cursorHoverObject) {
                                   if(event.button === Qt.LeftButton) {
                                       /* Begin grab immediately; release decides drag vs latch */
                                       worldGrabbing = true
                                       worldPressX = event.x
                                       worldPressY = event.y
                                       xrView.grab(true)
                                       return;
                                   }
                                   if(event.button === Qt.RightButton) {
                                       /* Begin selection prism. On release, motion-threshold
                                        * decides: prism commit (drag) vs radial menu (no drag). */
                                       xrView.prismBegin()
                                       if(xrView.radialMenuActivate(true)) {
                                           return;
                                       }
                                   }
                               }

                               event.accepted = false
                           }
                onPositionChanged: (event) => {
                               if (event.buttons & Qt.RightButton) {
                                   xrView.prismUpdate()
                               }
                           }
                onReleased: (event) => {
                                if(desktopGrabbed) {
                                    xrView.grab(false)
                                    desktopGrabbed = false
                                    return;
                                }

                                if(worldGrabbing) {
                                    const moved = (event.x !== worldPressX) || (event.y !== worldPressY)
                                    if(moved) {
                                        xrView.release()
                                    }
                                    worldGrabbing = false
                                    return;
                                }

                                if(event.button === Qt.RightButton && !xrView.cursorHoverObject) {
                                    /* Drag committed → prism, no radial. */
                                    if(xrView.prismCommit()) {
                                        return;
                                    }
                                    /* No drag → existing radial menu. */
                                    if(xrView.radialMenuActivate(false)) {
                                        return;
                                    }
                                } else if (event.button === Qt.RightButton) {
                                    xrView.prismCancel()
                                }
                            }
                onWheel: (event) => {
                             const dy = event.angleDelta.y
                             if (dy === 0)
                                 return
                             const direction = dy > 0 ? 1.0 : -1.0
                             const step = direction * KWinVRConfig.grabResizeSensitivity
                             if (event.modifiers & Qt.AltModifier) {
                                 xrView.curvatureNudge(direction)
                             } else if (event.modifiers & Qt.ShiftModifier) {
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
    }
}
