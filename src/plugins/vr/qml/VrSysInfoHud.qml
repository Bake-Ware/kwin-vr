/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later

    MangoHud-style system info overlay pinned to the camera in VR space.
    Activated/deactivated via KWinVRConfig.sysInfoEnabled.
*/

import QtQuick
import QtQuick3D
import org.kde.kwin.vr

Node {
    id: root

    required property var sysInfo   // KwinVrSysInfo instance
    property real cmWidth: 12.0     // physical width of the panel in world-space cm

    // Position relative to parent (camera node) — set from XrScene
    property vector3d hudPosition: Qt.vector3d(0, 0, -50)

    position: hudPosition

    // ── helpers ──────────────────────────────────────────────────────────────

    // Color-code a value between lo (green) and hi (red)
    function heatColor(value, lo, hi) {
        const t = Math.max(0, Math.min(1, (value - lo) / (hi - lo)))
        if (t < 0.5) return Qt.rgba(t * 2, 1.0, 0.0, 1.0)
        return Qt.rgba(1.0, 1.0 - (t - 0.5) * 2, 0.0, 1.0)
    }

    function mhzLabel(mhz) {
        return mhz >= 1000 ? (mhz / 1000).toFixed(1) + "G" : mhz + "M"
    }

    // ── frame timing (updated from FrameAnimation in XrScene) ────────────────
    // Driven externally via sysInfo.recordFrame(); properties are on sysInfo.

    // ── 2D panel rendered into a texture ─────────────────────────────────────
    Texture {
        id: panelTex
        sourceItem: Rectangle {
            id: panel
            width:  300
            height: 130
            color: "#dd000000"
            radius: 8

            // FPS row
            Row {
                id: fpsRow
                x: 10; y: 8
                spacing: 6

                Text {
                    text: "FPS"
                    color: "#aaaaaa"
                    font.pixelSize: 20
                    font.family: "monospace"
                    font.bold: true
                }
                Text {
                    text: root.sysInfo.fps > 0 ? root.sysInfo.fps.toFixed(0) : "--"
                    color: root.heatColor(root.sysInfo.fps, 60, 30)  // inverted: low FPS = red
                    font.pixelSize: 20
                    font.family: "monospace"
                    font.bold: true
                }
                Text {
                    text: root.sysInfo.frameTimeMs > 0
                          ? root.sysInfo.frameTimeMs.toFixed(1) + "ms"
                          : ""
                    color: root.heatColor(root.sysInfo.frameTimeMs, 16.7, 50)
                    font.pixelSize: 16
                    font.family: "monospace"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // CPU row
            Row {
                id: cpuRow
                x: 10
                anchors.top: fpsRow.bottom
                anchors.topMargin: 4
                spacing: 6

                Text { text: "CPU"; color: "#aaaaaa"; font.pixelSize: 16; font.family: "monospace"; font.bold: true }
                Text {
                    text: root.mhzLabel(root.sysInfo.cpuFreqBigMhz) + "/" + root.mhzLabel(root.sysInfo.cpuFreqLittleMhz)
                    color: "#dddddd"
                    font.pixelSize: 16
                    font.family: "monospace"
                }
                Text {
                    text: root.sysInfo.cpuUsagePercent + "%"
                    color: root.heatColor(root.sysInfo.cpuUsagePercent, 50, 90)
                    font.pixelSize: 16
                    font.family: "monospace"
                }
                Text {
                    text: root.sysInfo.cpuTempC + "°"
                    color: root.heatColor(root.sysInfo.cpuTempC, 60, 90)
                    font.pixelSize: 16
                    font.family: "monospace"
                }
            }

            // GPU row
            Row {
                id: gpuRow
                x: 10
                anchors.top: cpuRow.bottom
                anchors.topMargin: 4
                spacing: 6

                Text { text: "GPU"; color: "#aaaaaa"; font.pixelSize: 16; font.family: "monospace"; font.bold: true }
                Text {
                    text: root.mhzLabel(root.sysInfo.gpuFreqMhz)
                    color: "#dddddd"
                    font.pixelSize: 16
                    font.family: "monospace"
                }
                Text {
                    text: root.sysInfo.gpuLoadPercent + "%"
                    color: root.heatColor(root.sysInfo.gpuLoadPercent, 50, 90)
                    font.pixelSize: 16
                    font.family: "monospace"
                }
                Text {
                    text: root.sysInfo.gpuTempC + "°"
                    color: root.heatColor(root.sysInfo.gpuTempC, 60, 85)
                    font.pixelSize: 16
                    font.family: "monospace"
                }
            }

            // RAM row
            Row {
                id: ramRow
                x: 10
                anchors.top: gpuRow.bottom
                anchors.topMargin: 4
                spacing: 6

                Text { text: "RAM"; color: "#aaaaaa"; font.pixelSize: 16; font.family: "monospace"; font.bold: true }

                // Usage bar
                Rectangle {
                    width: 120
                    height: 14
                    color: "#333333"
                    radius: 3
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        width: root.sysInfo.ramTotalMb > 0
                               ? parent.width * root.sysInfo.ramUsedMb / root.sysInfo.ramTotalMb
                               : 0
                        height: parent.height
                        radius: parent.radius
                        color: root.heatColor(
                                   root.sysInfo.ramTotalMb > 0
                                   ? root.sysInfo.ramUsedMb * 100 / root.sysInfo.ramTotalMb
                                   : 0, 50, 90)
                    }
                }

                Text {
                    text: (root.sysInfo.ramUsedMb / 1024).toFixed(1) + "/" + (root.sysInfo.ramTotalMb / 1024).toFixed(0) + "G"
                    color: "#dddddd"
                    font.pixelSize: 16
                    font.family: "monospace"
                }
            }
        }
    }

    // ── 3D quad displaying the panel texture ─────────────────────────────────
    Model {
        property real w: root.cmWidth
        property real h: root.cmWidth * panel.height / panel.width

        source: "#Rectangle"
        scale: Qt.vector3d(w / 100, h / 100, 1)
        // Render on top of most scene geometry
        depthBias: -8000
        // Make the HUD ray-pickable; grabHandle points to root so the grab
        // system operates on the Node (push/pull moves it closer/farther).
        pickable: true
        property Node grabHandle: root

        materials: PrincipledMaterial {
            baseColorMap: panelTex
            alphaMode: PrincipledMaterial.Blend
            lighting: PrincipledMaterial.NoLighting
            cullMode: Material.NoCulling
        }
    }
}
