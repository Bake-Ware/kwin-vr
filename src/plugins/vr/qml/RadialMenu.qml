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

    // ========================================================================
    // Menu model — supports nested submenus via a stack
    // ========================================================================

    // Each menu item: { label: string, enabled: bool (optional, for toggle state) }
    // A submenu item: { label: string, submenu: [items...] }
    // The action logic lives in the signal handler (XrScene), not here.
    property var menuItems: []
    property var menuStack: []  // Stack of {items, parentLabel} for submenu navigation

    // The currently displayed items (top of stack or root)
    readonly property var currentItems: menuStack.length > 0 ? menuStack[menuStack.length - 1].items : menuItems
    readonly property int currentCount: currentItems ? currentItems.length : 0
    readonly property bool inSubmenu: menuStack.length > 0

    // Signals
    signal actionTriggered(string action)
    signal centerButtonClicked()
    signal closed()

    // Legacy compatibility — still used by RadialMenuNode aliases
    property list<string> buttonLabels: []
    property list<bool> buttonEnabled: []
    signal buttonClicked(int index)

    property real startWidth: 120
    property real startHeight: 120

    property bool closing: false
    function close() {
        closing = true
        wa.restart()
        ha.restart()
    }

    // Push a submenu onto the stack
    function pushSubmenu(items, parentLabel) {
        const stack = menuStack.slice()
        stack.push({ items: items, parentLabel: parentLabel })
        menuStack = stack
    }

    // Pop back to parent menu
    function popSubmenu() {
        if (menuStack.length > 0) {
            const stack = menuStack.slice()
            stack.pop()
            menuStack = stack
        }
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
                    root.menuStack = []  // Reset submenu stack on close
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
            model: root.currentCount > 0 ? root.currentCount : (root.buttonLabels.length > 0 ? root.buttonLabels.length : 5)

            Item {
                id: buttonContainer
                width: parent.width
                height: parent.height

                // Dynamic angle spacing based on button count
                property int buttonCount: root.currentCount > 0 ? root.currentCount : (root.buttonLabels.length > 0 ? root.buttonLabels.length : 5)
                rotation: index * (360 / buttonCount) - 90

                // Resolve the current menu item for this button
                property var menuItem: root.currentCount > 0 && root.currentItems[index] ? root.currentItems[index] : null
                property string itemLabel: menuItem ? (menuItem.label || "") : (root.buttonLabels[index] || ("Button " + (index + 1)))
                property bool itemEnabled: menuItem ? (menuItem.enabled || false) : (root.buttonEnabled[index] || false)
                property bool hasSubmenu: menuItem ? (menuItem.submenu !== undefined && menuItem.submenu !== null) : false

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
                    property color submenuColor: "#3d7abf"

                    color: buttonMouse.containsMouse ? startColor : (buttonContainer.hasSubmenu ? submenuColor : endColor)
                    border.color: buttonContainer.itemEnabled ? "#ff4444" : (buttonContainer.hasSubmenu ? "#ffa500" : "#5ab8ff")
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
                        text: buttonContainer.itemLabel + (buttonContainer.hasSubmenu ? " >" : "")
                        color: "white"
                        font.pixelSize: 14
                        font.bold: true
                        rotation: -buttonContainer.rotation
                    }

                    MouseArea {
                        id: buttonMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            console.log("RadialMenu click: index=", index,
                                        "label=", buttonContainer.itemLabel,
                                        "hasSubmenu=", buttonContainer.hasSubmenu,
                                        "menuItem=", JSON.stringify(buttonContainer.menuItem),
                                        "currentCount=", root.currentCount)
                            if (buttonContainer.hasSubmenu) {
                                // Navigate into submenu
                                root.pushSubmenu(buttonContainer.menuItem.submenu, buttonContainer.itemLabel)
                            } else if (buttonContainer.menuItem && buttonContainer.menuItem.action) {
                                // Fire action
                                root.actionTriggered(buttonContainer.menuItem.action)
                            } else {
                                // Legacy: fire index-based signal
                                root.buttonClicked(index)
                            }
                        }
                    }
                }
            }
        }

        // Center circle — acts as close/back button
        Rectangle {
            anchors.centerIn: parent
            width: 60
            height: 60
            radius: 30
            border.color: root.inSubmenu ? "#ffa500" : "#5ab8ff"
            border.width: 2

            property color startColor: root.inSubmenu ? "#85ff8800" : "#85fd0000"
            property color endColor: root.inSubmenu ? "#002200ff" : "#000018ff"
            color: centerButtonMouse.containsMouse ? startColor : endColor

            Behavior on color { ColorAnimation { duration: 200 } }

            Text {
                anchors.centerIn: parent
                text: root.inSubmenu ? "<" : ""
                color: "white"
                font.pixelSize: 20
                font.bold: true
                visible: root.inSubmenu
            }

            MouseArea {
                id: centerButtonMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (root.inSubmenu) {
                        root.popSubmenu()
                    } else {
                        centerButtonClicked()
                    }
                }
            }
        }
    }
}
