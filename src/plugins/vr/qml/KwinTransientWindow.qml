/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import org.kde.kwin.vr

Node {
    id: root
    visible: !root.client.minimized && (!KwinVrHelpers.screenLocked || client.lockScreen || client.lockScreenOverlay || client.inputMethod)

    required property KwinWindowModel windowDataModel
    required property Component nextComponent

    // Replaced aliases with properties to support Loader3D
    required property QtObject client
    property real ppu: 20
    property Node grabHandle

    property real normalWindowFlexibleBottom: 0
    property real zOffsetGlobal: 0

    required property VrFocusControl focusControl
    Connections {
        target: root.client
        function onMoveResizedChanged() {
            console.log(Logger.kwinvr, "Window move/resize changed:", root.client.resize, root.client.move, root.focusControl.currentMovingResizingWindow)
            if(root.client.resize || root.client.move) {
                root.focusControl.currentMovingResizingWindow = windowLoader.item
            } else if(root.focusControl.currentMovingResizingWindow === windowLoader.item) {
                root.focusControl.currentMovingResizingWindow = null
            }
        }
    }

    Component {
        id: decoratedSurfaceComponent
        KwinDecoratedSurfacedWindow3D {
            client: root.client
            ppu: root.ppu
            grabHandle: root.grabHandle
            zOffsetGlobal: root.zOffsetGlobal
        }
    }

    Component {
        id: thumbnailComponent
        KwinWindowThumbnail3D {
            client: root.client
            ppu: root.ppu
            grabHandle: root.grabHandle
            zOffsetGlobal: root.zOffsetGlobal
        }
    }

    Component {
        id: thumbnailXrItemComponent
        KwinWindowThumbnailXrItem {
            client: root.client
            ppu: root.ppu
            grabHandle: root.grabHandle
            zOffsetGlobal: root.zOffsetGlobal
        }
    }

    //  1. Draw the main window using Loader3D based on configuration
    Loader3D {
        id: windowLoader
        sourceComponent: {
            switch(KWinVRConfig.windowMode) {
                case 0: return decoratedSurfaceComponent; // DecoratedSurface
                case 1: return thumbnailComponent; // Thumbnail
                case 2: return thumbnailXrItemComponent; // ThumbnailXrItem
                default: return thumbnailXrItemComponent;
            }
        }
    }

    //  2. Draw the stack of transient menus always above the main window
    // (currently not only menus, but all non top-level windows)
    Repeater3D {
        id: menuRepeater
        model: TransientMenusWindowFilter {
            forTransient: root.client
            windowModel: root?.client?.managed ? root.windowDataModel : null
        }
        delegate: root.nextComponent
    }
    ZStacker {
        id: menuStack
        target: menuRepeater
        // Use loaded item's itemDepth if available, else default
        initalMargins: windowLoader.item ? windowLoader.item.itemDepth : ({top: 1, bottom: 0})
        childIndexProperyName: "stackingOrder"
        globalOffset: root.zOffsetGlobal
    }

    //  3. Draw the stack of normal transient windows always above menu stack
    Repeater3D {
        id: transientNormalsRepeater
        model: TransientNormalWindowFilter {
            forTransient: root.client
            windowModel: root?.client?.managed ? root.windowDataModel : null
        }
        delegate: root.nextComponent
    }
    ZStacker {
        id: transientNormalsStack
        target: transientNormalsRepeater
        initalMargins: menuStack.depth
        childIndexProperyName: "stackingOrder"
        globalOffset: menuStack.depth.top + (windowLoader.item?.zOffsetGlobal ?? root.zOffsetGlobal)
    }

    // 4. Get total depth: If the main window was a normal window then add flexible bottom
    property zMargins itemDepth:  ({
                                       top: transientNormalsStack.depth.top,
                                       bottom: transientNormalsStack.depth.bottom,
                                       flexibleTop: 0,
                                       flexibleBottom: (root.client.normalWindow && root.visible) ? root.normalWindowFlexibleBottom : 0,
                                   })
}
