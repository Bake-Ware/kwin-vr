/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D.Xr
import org.kde.kwin.vr

/* VR controller buttons mappings */
Item {
    id: root
    property KwinVrInputDevice kwinInput

    // Controller definitions
    readonly property var controllers: [
        { controller: XrInputAction.LeftController, prefix: "left" },
        { controller: XrInputAction.RightController, prefix: "right" }
    ]

    // Action definitions for boolean inputs
    readonly property var booleanActions: [
        { actionId: XrInputAction.Button1Pressed, configSuffix: "Button1Pressed" },
        { actionId: XrInputAction.Button1Touched, configSuffix: "Button1Touched" },
        { actionId: XrInputAction.Button2Pressed, configSuffix: "Button2Pressed" },
        { actionId: XrInputAction.Button2Touched, configSuffix: "Button2Touched" },
        { actionId: XrInputAction.ButtonMenuPressed, configSuffix: "ButtonMenuPressed" },
        { actionId: XrInputAction.ButtonMenuTouched, configSuffix: "ButtonMenuTouched" },
        { actionId: XrInputAction.ButtonSystemPressed, configSuffix: "ButtonSystemPressed" },
        { actionId: XrInputAction.ButtonSystemTouched, configSuffix: "ButtonSystemTouched" },
        { actionId: XrInputAction.TriggerTouched, configSuffix: "TriggerTouched" },
        { actionId: XrInputAction.ThumbstickPressed, configSuffix: "ThumbstickPressed" },
        { actionId: XrInputAction.ThumbstickTouched, configSuffix: "ThumbstickTouched" },
        { actionId: XrInputAction.ThumbrestTouched, configSuffix: "ThumbrestTouched" },
        { actionId: XrInputAction.TrackpadTouched, configSuffix: "TrackpadTouched" },
        { actionId: XrInputAction.TrackpadPressed, configSuffix: "TrackpadPressed" },
        { actionId: XrInputAction.IndexFingerPinch, configSuffix: "IndexFingerPinch" },
        { actionId: XrInputAction.MiddleFingerPinch, configSuffix: "MiddleFingerPinch" },
        { actionId: XrInputAction.RingFingerPinch, configSuffix: "RingFingerPinch" },
        { actionId: XrInputAction.LittleFingerPinch, configSuffix: "LittleFingerPinch" },
        { actionId: XrInputAction.HandTrackingMenuPress, configSuffix: "HandTrackingMenuPress" }
    ]

    // Action definitions for analog inputs (value + pressed, with threshold)
    readonly property var analogActions: [
        { actionId: [XrInputAction.SqueezeValue, XrInputAction.SqueezePressed],
          configSuffix: "SqueezePressed", thresholdSuffix: "SqueezeValue" },
        { actionId: [XrInputAction.TriggerValue, XrInputAction.TriggerPressed],
          configSuffix: "TriggerPressed", thresholdSuffix: "TriggerValue" }
    ]

    // Action definitions for thumbstick scroll
    readonly property var thumbstickActions: [
        { actionId: XrInputAction.ThumbstickX, configSuffix: "ThumbstickX", isVertical: false },
        { actionId: XrInputAction.ThumbstickY, configSuffix: "ThumbstickY", isVertical: true }
    ]

    readonly property var mouseBindings: ({
        "MouseLeft": "leftButton",
        "MouseMiddle": "middleButton",
        "MouseRight": "rightButton",
        "MouseBack": "backButton",
        "MouseForward": "forwardButton"
    })

    function isValidBinding(binding) {
        return binding && binding !== "" && binding !== "none";
    }

    function createHandler(binding) {
        const prop = mouseBindings[binding];
        if (prop) {
            return (pressed) => { kwinInput[prop] = pressed; };
        } else {
            const code = kwinInput.resolveKeyCode(binding);
            return (pressed) => { kwinInput.sendKeyCode(code, pressed); };
        }
    }

    // Main controller repeater - creates bindings for each controller
    Repeater {
        model: root.controllers
        delegate: Item {
            id: controllerDelegate
            required property var modelData
            readonly property int ctrl: modelData.controller
            readonly property string prefix: modelData.prefix

            // Boolean actions (button presses/touches)
            Repeater {
                model: root.booleanActions
                delegate: Loader {
                    id: booleanLoader
                    required property var modelData
                    readonly property string configName: controllerDelegate.prefix + modelData.configSuffix
                    readonly property int actionId: modelData.actionId
                    readonly property var handler: createHandler(KWinVRConfig[configName])
                    active: isValidBinding(KWinVRConfig[configName])
                    sourceComponent: XrInputAction {
                        controller: controllerDelegate.ctrl
                        actionId: booleanLoader.actionId
                        onPressedChanged: booleanLoader.handler(pressed)
                    }
                }
            }

            // Analog actions (squeeze/trigger with threshold)
            Repeater {
                model: root.analogActions
                delegate: Loader {
                    id: analogLoader
                    required property var modelData
                    readonly property string configName: controllerDelegate.prefix + modelData.configSuffix
                    readonly property string thresholdName: controllerDelegate.prefix + modelData.thresholdSuffix
                    readonly property var actionId: modelData.actionId
                    readonly property var handler: createHandler(KWinVRConfig[configName])
                    active: isValidBinding(KWinVRConfig[configName]) && KWinVRConfig[thresholdName] > 0
                    sourceComponent: XrInputAction {
                        controller: controllerDelegate.ctrl
                        actionId: analogLoader.actionId
                        onValueChanged: analogLoader.handler(value >= KWinVRConfig[analogLoader.thresholdName])
                    }
                }
            }

            // Thumbstick scroll actions
            Repeater {
                model: root.thumbstickActions
                delegate: Loader {
                    id: thumbstickLoader
                    required property var modelData
                    readonly property string configName: controllerDelegate.prefix + modelData.configSuffix
                    readonly property real configScale: KWinVRConfig[configName]
                    readonly property int actionId: modelData.actionId
                    readonly property var handler: modelData.isVertical
                        ? (delta) => { kwinInput.setAxis(delta * -1, 0); }
                        : (delta) => { kwinInput.setAxis(0, delta); }
                    active: configScale !== 0
                    sourceComponent: XrInputAction {
                        controller: controllerDelegate.ctrl
                        actionId: thumbstickLoader.actionId
                        property FrameAnimation frameAnim: FrameAnimation {
                            running: Math.abs(value) >= 0.05
                            onTriggered: thumbstickLoader.handler(value * thumbstickLoader.configScale * frameTime * 500)
                        }
                    }
                }
            }
        }
    }
}
