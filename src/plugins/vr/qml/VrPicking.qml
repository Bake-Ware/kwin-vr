/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D
import QtQuick3D.Xr

import org.kde.kwin.vr

QtObject {
    id: root

    required property Xray xray
    required property XrView xrView

    // we can't create empty pick, so this value is used as a source of emptiness
    property pickResult emptyPick

    // Contains the topmost pick result for the object that has agreed to be picked
    property pickResult lastPick
    property list<pickResult> lastAllPicks

    // This is always a 3D object that is currently hovered,
    // if a 2D Item is being hovered, then this property will hold the closest 3D parent of the 2D Item
    property Node hoveredObject

    readonly property Item hoveredItem: root.lastPick.itemHit

    readonly property Node hoveredGrabHandle: hoveredObject?.grabHandle ?? null

    function updateAllPicks(): void {
        if (!root.xrView || !root.xrView.environment)
            return
        root.lastAllPicks = root.xrView.rayPickAll(root.xray.scenePosition, root.xray.forward)
        processAllPicks()
    }

    function acceptedPickObject(pickResult: pickResult): Node {
        const obj = pickResult.objectHit ?? root.getHoveredNodeFromItem(pickResult.itemHit)
        if (!obj) {
            return null
        }
        if (!obj.onPick) {
            return obj
        }
        return obj.onPick(pickResult) ? obj : null
    }

    // This function improves picking process by calling onPick method if it is present
    // This way the picked Model can refuse to be picked dynamically
    function processAllPicks(): void {
        const pa = root.lastAllPicks
        for (const p of pa) {
            const obj = root.acceptedPickObject(p)
            if (obj) {
                // Order matters here
                root.hoveredObject = obj
                root.lastPick = p
                return
            }
        }
        root.lastPick = root.emptyPick
        root.hoveredObject = null
    }

    property bool rendererReady: false

    readonly property Timer rendererCheck: Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            if (root.xrView && root.xrView.environment) {
                root.rendererReady = true
                stop()
            }
        }
    }

    readonly property Connections pickingConnections: Connections {
        target: root.xray
        enabled: root.xray.enabled && root.rendererReady
        function onSceneTransformChanged(): void {
            root.updateAllPicks()
        }
    }

    /** For 2D items to be supported they need parent3d property to be set to the closest 3D object
     * Node {
     *     id: node
     *     Rectangle {
     *         property Node parent3d: node
     *     }
     * }
     *
     * XrItem {
     *     id: xritem
     *     contentItem: Rectangle {
     *         property Node parent3d: xritem
     *     }
     * }
     *
     */
    function getHoveredNodeFromItem(curItem: Item): Node {
        if(!curItem)
            return null

        const parent3d = curItem.parent3d as Node;
        if(parent3d)
            return parent3d

        //XrItem wraps it's contentItem in a Rectangle that we can't control
        //So let's test if the first child has parent3d property
        if (curItem.children.length > 0) {
            const maybeXrItemParent = curItem.children[0].parent3d as Node;
            if(maybeXrItemParent)
                return maybeXrItemParent
        }

        let itemParent = curItem.parent;
        while(itemParent) {
            const parent3d =  itemParent.parent3d as Node;
            if(parent3d)
                return parent3d

            itemParent = itemParent.parent
        }
        return null
    }

    function isGrabHandlePicked(handle: Node): bool {
        if (!handle) {
            return false
        }

        const allPicks = root.lastAllPicks
        for (const pickResult of allPicks) {
            const obj = root.acceptedPickObject(pickResult)
            if (!obj) {
                continue
            }
            const pickHandle = obj.grabHandle ?? obj
            if (pickHandle === handle) {
                return true
            }
        }
        return false
    }
}
