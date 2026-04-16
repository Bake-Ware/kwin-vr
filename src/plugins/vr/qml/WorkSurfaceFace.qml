/*
    SPDX-FileCopyrightText: 2026 KWin-VR Contributors

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

/*
 * A single face of a work surface that can host windows.
 *
 * Modeled after KwinPseudoOutputMirror: provides a pickable surface,
 * UV-to-local coordinate conversion, and ZStacker for window depth.
 * Windows reparent here when snapped to this face.
 */
Node {
    id: root

    property int faceIndex: 0
    property int layoutMode: WorkSurfaceLayout.Masonry
    property int activeIndex: 0

    // Face dimensions in world units (set by parent WorkSurface3D)
    property real faceWidth: 50
    property real faceHeight: 35
    property real ppu: 20

    // Region geometry descriptor. Flat by default; curved regions override.
    //   FlatRect:     window renders as a tilted flat quad.
    //   CylinderBody: window wraps an arc of regionRadius at attach time,
    //                 arcAngle = windowWidth / regionRadius. regionArcAngle
    //                 here is an informational upper bound (full face arc).
    //   SpherePatch:  window renders as a spherical cap of regionRadius,
    //                 angular extents derived from window size.
    property int regionKind: WorkSurfaceRegion.FlatRect
    property real regionRadius: 30
    property real regionArcAngle: 0
    property real regionPatchWidthAngle: 0
    property real regionPatchHeightAngle: 0

    // Size for SpaceAllocator3D (if face were independently tracked)
    property size itemSize: Qt.size(faceWidth, faceHeight)

    // Visual hover state — set by VrWindowManipulation while dragging over this face
    property bool hovered: false

    // Resolve the delegate once, then bind reactively to its selected state
    property var _delegate: null
    Component.onCompleted: {
        let n = root.parent
        while (n) {
            if (n.isWorkSurface) { _delegate = n; break }
            n = n.parent
        }
    }
    readonly property bool selected: _delegate ? _delegate.selected : false

    // List of attached KwinApplicationWindows
    property var attachedWindows: []

    // Reference to the layout engine singleton
    property WorkSurfaceLayoutEngine layoutEngine: WorkSurfaceLayoutEngine

    // Grab handle — the parent work surface is the grab target
    property Node grabHandle: root.parent

    // Invisible pickable face proxy. The primitive's wireframe (drawn at the
    // shape level in XrScene.qml) carries all the visual. This Model exists
    // solely to receive drag-target ray hits and provide face geometry/UV
    // coordinates for snap computation.
    Model {
        id: faceModel
        source: "#Rectangle"
        pickable: true
        scale: Qt.vector3d(root.faceWidth / 100, root.faceHeight / 100, 0.001)
        materials: PrincipledMaterial {
            baseColor: "#00000000"
            alphaMode: PrincipledMaterial.Blend
            lighting: PrincipledMaterial.NoLighting
            depthDrawMode: Material.NeverDepthDraw
            cullMode: Material.NoCulling
        }
    }

    // ZStacker for window depth ordering within this face
    property alias itemDepth: stacker.depth
    ZStacker {
        id: stacker
        target: root
        childIndexPropertyName: "stackingOrder"
        initialMargins: ({top: 0.2, bottom: 0})
        globalOffset: 0
    }

    // Convert UV coordinates (0-1) from a ray pick to local 3D position on this face
    function uvToLocalPosition(coords) {
        // UV origin is bottom-left, Y inverted
        const x = (coords.x - 0.5) * root.faceWidth
        const y = (coords.y - 0.5) * root.faceHeight
        return Qt.vector3d(x, y, 0)
    }

    // Attach a window to this face
    function attachWindow(appWin) {
        if (root.attachedWindows.indexOf(appWin) >= 0) {
            return
        }

        const windows = root.attachedWindows.slice()
        windows.push(appWin)
        root.attachedWindows = windows

        appWin.attachedFace = root
        appWin.parent = root

        if (root._delegate && root._delegate.noteFaceHostedChanged)
            root._delegate.noteFaceHostedChanged(+1)

        relayout()
    }

    // Detach a window from this face
    function detachWindow(appWin) {
        const idx = root.attachedWindows.indexOf(appWin)
        if (idx < 0) {
            return
        }

        const windows = root.attachedWindows.slice()
        windows.splice(idx, 1)
        root.attachedWindows = windows

        appWin.attachedFace = null

        // Clamp activeIndex
        if (root.activeIndex >= root.attachedWindows.length) {
            root.activeIndex = Math.max(0, root.attachedWindows.length - 1)
        }

        if (root._delegate && root._delegate.noteFaceHostedChanged)
            root._delegate.noteFaceHostedChanged(-1)

        relayout()
    }

    // Per-layer radial offset for Stack-on-curved-region ("onion") layout.
    // Tuned to match the pseudo-output z-stack visual step.
    readonly property real _onionStep: 0.5

    // Recompute window positions using the layout engine. Flat regions place
    // windows in the face's xy-plane; curved regions rotate the window Node so
    // its +Z axis points at the correct point on the primitive surface, and the
    // window's own curved mesh (CylinderBodyGeometry / SpherePatchGeometry) lays
    // the pixels on the surface.
    function relayout() {
        const windows = root.attachedWindows
        if (windows.length === 0) {
            return
        }

        // Collect window sizes in world units
        const windowSizes = []
        for (let i = 0; i < windows.length; ++i) {
            const win = windows[i]
            const geom = win.client ? win.client.frameGeometry : Qt.rect(0, 0, 100, 100)
            windowSizes.push(Qt.size(geom.width / root.ppu, geom.height / root.ppu))
        }

        const faceSize = Qt.size(root.faceWidth, root.faceHeight)
        const slots = root.layoutEngine.computeLayout(root.layoutMode, faceSize, windowSizes, root.activeIndex)
        const isStack = root.layoutMode === WorkSurfaceLayout.Stack

        for (let i = 0; i < windows.length && i < slots.length; ++i) {
            const win = windows[i]
            const slot = slots[i]

            // Slot center in unrolled face coordinates (face center = origin).
            const cx = slot.rect.x + slot.rect.width / 2 - root.faceWidth / 2
            const cy = -(slot.rect.y + slot.rect.height / 2 - root.faceHeight / 2)

            if (root.regionKind === WorkSurfaceRegion.CylinderBody && root.regionRadius > 0.001) {
                // Wrap cx around cylinder axis (Y). Window Node sits on the axis;
                // its rotation around Y orients it to face outward at angle θ.
                // The window's own mesh (CylinderBodyGeometry) bulges out to r.
                const theta = cx / root.regionRadius
                const stackExtra = isStack ? (slot.zOrder * root._onionStep) : 0
                win.position = Qt.vector3d(
                    stackExtra * Math.sin(theta),
                    cy,
                    stackExtra * Math.cos(theta))
                win.rotation = KwinVrHelpers.rotationBetweenVectors(
                    Qt.vector3d(0, 0, 1),
                    Qt.vector3d(Math.sin(theta), 0, Math.cos(theta)))
            } else if (root.regionKind === WorkSurfaceRegion.SpherePatch && root.regionRadius > 0.001) {
                // Map (cx, cy) on the unrolled patch to a direction on the sphere.
                // φ is latitude (cy → vertical angle). θ is longitude
                // (cx scaled by cos(φ) to approximate arc length at that latitude).
                const phi = cy / root.regionRadius
                const cosPhi = Math.max(Math.cos(phi), 0.001)
                const theta = cx / (root.regionRadius * cosPhi)
                const dir = Qt.vector3d(
                    Math.cos(phi) * Math.sin(theta),
                    Math.sin(phi),
                    Math.cos(phi) * Math.cos(theta))
                // Stack onion: push outward radially by stack order.
                const stackExtra = isStack ? (slot.zOrder * root._onionStep) : 0
                win.position = Qt.vector3d(
                    dir.x * stackExtra,
                    dir.y * stackExtra,
                    dir.z * stackExtra)
                win.rotation = KwinVrHelpers.rotationBetweenVectors(
                    Qt.vector3d(0, 0, 1), dir)
            } else {
                // FlatRect
                win.position = Qt.vector3d(cx, cy, 0)
                win.rotation = Qt.quaternion(1, 0, 0, 0)
            }
        }
    }

    // Cycle through windows in stack/cover mode
    function cycleActiveIndex(delta) {
        if (root.attachedWindows.length <= 1) {
            return
        }
        root.activeIndex = (root.activeIndex + delta + root.attachedWindows.length) % root.attachedWindows.length
        relayout()
    }
}
