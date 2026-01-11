/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls


Rectangle {
    id: root
    width: 300
    height: 300
    color: "transparent"

    focus: true

    Keys.onPressed: (event) => {
         if (event.key === Qt.Key_Escape) {
             event.accepted = true
         }
    }

    Keys.onReleased: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
        }
    }
    
    Component.onDestruction: {
        // Release focus explicitly to prevent a crash in QQuickWindowPrivate::polishItems
        // which can occur when a focused item is destroyed while being rendered in VR.
        root.focus = false
    }

    Timer {
        // Request focus after a short delay because calling forceActiveFocus() 
        // in Component.onCompleted is too early and often fails to grab focus.
        interval: 50
        running: true
        repeat: false
        onTriggered: {
            root.forceActiveFocus()
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onPressed: (mouse) => {
            root.forceActiveFocus()
            mouse.accepted = false
        }
    }

    property list<string> buttonLabels: ["Button 1", "Button 2", "Button 3", "Button 4", "Button 5"]
    property list<bool> buttonEnabled: [false, false, false, false, false]
    signal buttonClicked(int index)
    signal centerButtonClicked()
    signal closed()

    property real startWidth: 120
    property real startHeight: 120

    property bool closing: false
    function close() {
        closing = true
        wa.restart()
        ha.restart()
    }

    Item {
        id: radialMenu
        anchors.centerIn: parent
        width: root.width
        height: root.height

        NumberAnimation on width {
            id: wa
            from: root.closing ? root.width : root.startWidth
            to: root.closing ?  root.startWidth : root.width
            duration: root.closing ? 90 : 180
            loops: 1
            onRunningChanged: {
                if(!running && root.closing) {
                    root.closing = false
                    root.closed()
                }
            }
        }
        NumberAnimation on height {
            id: ha
            from: root.closing ? root.height : root.startHeight
            to: root.closing ?  root.startHeight : root.height
            duration: root.closing ? 90 : 180
            loops: 1
        }

        Repeater {
            model: 5

            Item {
                id: buttonContainer
                width: parent.width
                height: parent.height
                rotation: index * 72 - 90

                Rectangle {
                    id: button
                    x: parent.width / 2 - width / 2
                    y: 30
                    width: 100
                    height: 80

                    // Rounded trapezoid shape
                    radius: 12
                    property color startColor: "#4a9eff"
                    property color endColor: "#2d5a8f"

                    color: buttonMouse.containsMouse ? startColor : endColor
                    border.color: root.buttonEnabled[index] ? "#ff4444" : "#5ab8ff"
                    border.width: 2
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    transform: [
                        Scale {
                            origin.x: button.width / 2
                            origin.y: button.height / 2
                            xScale: buttonMouse.pressed ? 0.9 : 1.0
                            yScale: buttonMouse.pressed ? 0.9 : 1.0
                            Behavior on xScale { NumberAnimation { duration: 100 } }
                            Behavior on yScale { NumberAnimation { duration: 100 } }
                        }
                    ]

                    Behavior on color { ColorAnimation { duration: 200 } }

                    Text {
                        anchors.centerIn: parent
                        text: root.buttonLabels[index]
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                        rotation: -buttonContainer.rotation
                    }

                    MouseArea {
                        id: buttonMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.buttonClicked(index)
                    }
                }
            }
        }

        // Center circle
        Rectangle {
            anchors.centerIn: parent
            width: 60
            height: 60
            radius: 30
            border.color: "#5ab8ff"
            border.width: 2

            property color startColor: "#85fd0000"
            property color endColor: "#000018ff"
            color: centerButtonMouse.containsMouse ? startColor : endColor

            Behavior on color { ColorAnimation { duration: 200 } }
            MouseArea {
                id: centerButtonMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: centerButtonClicked()
            }
        }
    }
}
