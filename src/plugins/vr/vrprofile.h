/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QList>
#include <QString>

namespace KWin
{

/**
 * Describes a VR headset profile loaded from /etc/vr-profiles.d/ (*.conf files).
 *
 * Key fields:
 *  - connectorName: KWin output name, e.g. "HDMI-A-1", "DP-1"
 *  - usbId: "VID:PID" used to confirm the right device is on the connector
 *  - autoStart: true  → activate VR as soon as the output appears (Samsung)
 *               false → watch for SBS mode change to trigger VR (Xreal)
 */
struct VrProfile {
    QString name;
    QString usbId;         // "VID:PID", empty = skip USB check
    QString connectorName; // KWin output name
    int width = 0;         // 2D/native width  (also VR activation width for autoStart)
    int height = 0;
    int refresh = 60;
    float scale = 1.0f;
    bool autoStart = false;

    bool isValid() const { return !connectorName.isEmpty() && width > 0; }

    // For non-autoStart profiles the SBS trigger is any mode wider than 'width'.
    // (Xreal Air: 1920→3840 on button press)
    bool isSbsMode(int modeWidth) const { return !autoStart && modeWidth > width; }
};

class VrProfileLoader
{
public:
    static QList<VrProfile> loadProfiles(const QString &dir = QStringLiteral("/etc/vr-profiles.d"));
    static bool isUsbDevicePresent(const QString &usbId);
};

} // namespace KWin
