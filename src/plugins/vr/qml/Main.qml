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

    VrMouseBindings {
        id: mouseBindings
        kwinInput: kwinInput
    }

    HeadScrollBindings {
        id: headScrollBindings
    }

    // TODO: need to move all input related stuff to the better place
    MouseArea {
        id: mouseArea
        focus: true
        Keys.onPressed: (event) => {
                            xrView.closeRadialMenu();

                            if (mouseBindings.handleKey(event, true)) {
                                event.accepted = true
                                return
                            }

                            if (!event.isAutoRepeat && headScrollBindings.isHeadScrollKey(event.key, event.modifiers)) {
                                xrView.headScrollActive = true
                                event.accepted = true
                                return
                            }

                            if(xrView.grabbed) {
                                if(event.modifiers & Qt.ShiftModifier) {
                                    if(event.key === Qt.Key_Right) {
                                        xrView.resizeRight = true; event.accepted = true
                                    } else if(event.key === Qt.Key_Left) {
                                        xrView.resizeLeft = true; event.accepted = true
                                    } else if(event.key === Qt.Key_Up) {
                                        xrView.resizeUp = true; event.accepted = true
                                    } else if(event.key === Qt.Key_Down) {
                                        xrView.resizeDown = true; event.accepted = true
                                    }
                                } else if(event.key === Qt.Key_Up) {
                                    xrView.pushGrabbed = true
                                    event.accepted = true
                                } else if(event.key === Qt.Key_Down) {
                                    xrView.pullGrabbed = true
                                    event.accepted = true
                                } else if(event.key === Qt.Key_Right) {
                                    xrView.curveBigger = true
                                    event.accepted = true
                                } else if(event.key === Qt.Key_Left) {
                                    xrView.curveSmaller = true
                                    event.accepted = true
                                }
                            }
                        }
        Keys.onReleased: (event) => {
                             if (mouseBindings.handleKey(event, false)) {
                                 event.accepted = true
                                 return
                             }

                             if (headScrollBindings.isHeadScrollKey(event.key, event.modifiers)) {
                                 xrView.headScrollActive = false
                                 event.accepted = true
                                 return
                             }

                             if(xrView.grabbed) {
                                 if(event.key === Qt.Key_Right) {
                                     xrView.resizeRight = false
                                     xrView.curveBigger = false
                                     event.accepted = true
                                 } else if(event.key === Qt.Key_Left) {
                                     xrView.resizeLeft = false
                                     xrView.curveSmaller = false
                                     event.accepted = true
                                 } else if(event.key === Qt.Key_Up) {
                                     xrView.resizeUp = false
                                     xrView.pushGrabbed = false
                                     event.accepted = true
                                 } else if(event.key === Qt.Key_Down) {
                                     xrView.resizeDown = false
                                     xrView.pullGrabbed = false
                                     event.accepted = true
                                 }
                             }
                         }


        acceptedButtons: Qt.AllButtons

        property bool desktopGrabbed: false
        onPressed: (event) => {
                       /* Release grabbed object on any button press */
                       if(xrView.release()) {
                            /* Nedd to send key press further for kwin to release thw window */
                           if(xrView.currentMovingResizingWindow) {
                               event.accepted = false
                           }
                           return;
                       }

                       if (headScrollBindings.isHeadScrollButton(event.button)) {
                           xrView.headScrollActive = true;
                           return;
                       }

                       if(event.modifiers & Qt.MetaModifier) {
                           desktopGrabbed = xrView.grabDesktop()
                           if(desktopGrabbed) {
                               return;
                           }
                       }

                       /* Activate/close radial menu if click on empty space */
                       if(xrView.radialMenuActivate(true)) {
                           return;
                       }

                       event.accepted = false
                   }
        onReleased: (event) => {
                        if(desktopGrabbed) {
                            xrView.grab(false)
                            desktopGrabbed = false
                            return;
                        }

                        if (headScrollBindings.isHeadScrollButton(event.button)) {
                            xrView.headScrollActive = false;
                        }

                        if(xrView.radialMenuActivate(false)) {
                            return;
                        }
                    }
        onWheel: (event) => {
                     // Wheel events are always accepted :(
                 }
    }

    XrScene {
        id: xrView
        kwinInput: kwinInput
        kwinInputFilter: kwinInputFIlter
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
        function onResetViewTriggered() { xrView.resetView() }
        function onTogglePipTriggered() { xrView.togglePip() }
        function onOpenRadialMenuTriggered() {
            xrView.toggleRadialMenu()
        }
    }
}
