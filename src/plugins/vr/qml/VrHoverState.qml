/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick3D

import org.kde.kwin.vr

QtObject {
    id: root

    required property Node hoveredObject

    // Current hovered objects by type
    readonly property VrHudWindow currentHoveredVrHudWindow: hoveredObject?.parent as VrHudWindow
    readonly property KwinPseudoOutputMirror currentHoveredKwinPseudoOutputMirror: hoveredObject?.parent as KwinPseudoOutputMirror
    readonly property KwinWindowThumbnail3D currentHoveredKwinWindowThumbnail3D: hoveredObject?.parent as KwinWindowThumbnail3D
    readonly property KwinWindowThumbnailXrItem currentHoveredKwinWindowThumbnailXrItem: hoveredObject?.parent as KwinWindowThumbnailXrItem
    readonly property KwinWaylandSurface3D currentHoveredKwinWaylandSurface3D: hoveredObject?.parent as KwinWaylandSurface3D
    readonly property KwinDecorationModel currentHoveredKwinDecorationModel: hoveredObject as KwinDecorationModel
    readonly property KwinInternalWindow3D currentHoveredKwinInternalWindow3D: hoveredObject?.parent as KwinInternalWindow3D
    readonly property CurvedWindowContent currentHoveredCurvedWindow: hoveredObject?.parent as CurvedWindowContent

    /*
     * Picking handler - set by pickingState based on hovered window type.
     * Single object assignment ensures atomicity during state transitions.
     */
    property var activePickHandler: null

    // Picking state - what window type is being hovered (independent of moving/resizing)
    readonly property StateGroup pickingState: StateGroup {
        states: [
            State {
                name: "hudWindow"
                when: !!root.currentHoveredVrHudWindow?.client
                PropertyChanges {
                    root.activePickHandler: ({
                        target: root.currentHoveredVrHudWindow,
                        client: root.currentHoveredVrHudWindow.client,
                        geometry: root.currentHoveredVrHudWindow.client.frameGeometry
                    })
                }
            },
            State {
                name: "pseudoOutput"
                when: !!root.currentHoveredKwinPseudoOutputMirror?.output
                PropertyChanges {
                    root.activePickHandler: ({
                        target: root.currentHoveredKwinPseudoOutputMirror,
                        client: null,
                        geometry: root.currentHoveredKwinPseudoOutputMirror.output.geometry
                    })
                }
            },
            State {
                name: "thumbnail3D"
                when: !!root.currentHoveredKwinWindowThumbnail3D?.client
                PropertyChanges {
                    root.activePickHandler: ({
                        target: root.currentHoveredKwinWindowThumbnail3D,
                        client: root.currentHoveredKwinWindowThumbnail3D.client,
                        geometry: root.currentHoveredKwinWindowThumbnail3D.client.frameGeometry
                    })
                }
            },
            State {
                name: "thumbnailXrItem"
                when: !!root.currentHoveredKwinWindowThumbnailXrItem?.client
                PropertyChanges {
                    root.activePickHandler: ({
                        target: root.currentHoveredKwinWindowThumbnailXrItem,
                        client: root.currentHoveredKwinWindowThumbnailXrItem.client,
                        geometry: root.currentHoveredKwinWindowThumbnailXrItem.client.frameGeometry
                    })
                }
            },
            State {
                name: "surface3D"
                when: !!root.currentHoveredKwinWaylandSurface3D?.client
                PropertyChanges {
                    root.activePickHandler: ({
                        target: root.currentHoveredKwinWaylandSurface3D,
                        client: root.currentHoveredKwinWaylandSurface3D.client,
                        geometry: root.currentHoveredKwinWaylandSurface3D.client.bufferGeometry
                    })
                }
            },
            State {
                name: "decoration"
                when: !!root.currentHoveredKwinDecorationModel &&
                      !!(root.currentHoveredKwinDecorationModel.parent as KwinDecorations3D)?.client
                PropertyChanges {
                    root.activePickHandler: ({
                        target: root.currentHoveredKwinDecorationModel,
                        client: (root.currentHoveredKwinDecorationModel.parent as KwinDecorations3D).client,
                        geometry: (root.currentHoveredKwinDecorationModel.parent as KwinDecorations3D).client.frameGeometry
                    })
                }
            },
            State {
                name: "internalWindow"
                when: !!root.currentHoveredKwinInternalWindow3D?.client
                PropertyChanges {
                    root.activePickHandler: ({
                        target: root.currentHoveredKwinInternalWindow3D,
                        client: root.currentHoveredKwinInternalWindow3D.client,
                        geometry: root.currentHoveredKwinInternalWindow3D.client.clientGeometry
                    })
                }
            },
            State {
                name: "curvedWindow"
                when: !!root.currentHoveredCurvedWindow?.client
                PropertyChanges {
                    root.activePickHandler: ({
                        target: root.currentHoveredCurvedWindow,
                        client: root.currentHoveredCurvedWindow.client,
                        geometry: root.currentHoveredCurvedWindow.client.frameGeometry
                    })
                }
            }
        ]
    }

    readonly property Node desktopOrDockHovered: {
        const client = activePickHandler?.client
        return (client && (client.dock || client.desktopWindow)) ? activePickHandler.target : null
    }
}
