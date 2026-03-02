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
 * How a VR device is identified at runtime.
 *
 * Display: matched by EDID monitor name (+ optional USB VID:PID).
 *          Activates VR when the display enters the configured SBS resolution.
 *          If sbsWidth/sbsHeight are 0 the headset triggers VR on connect (e.g. Samsung Odyssey+).
 *
 * Service: matched by a D-Bus service name (e.g. WiVRn).
 *          Activates VR when the service appears on the session bus.
 *          Display-type profiles take priority over service-type ones.
 */
enum class VrDetectType {
    Display,
    Service,
};

/**
 * VR headset profile loaded from /etc/vr-profiles.d/ (*.conf files).
 */
struct VrProfile {
    QString name;
    VrDetectType detectType = VrDetectType::Display;

    // Display-type fields
    QString edidName; // EDID 0xFC monitor name substring, e.g. "Air"
    QString usbId; // optional "VID:PID" to confirm correct device on connector
    QString connectorHint; // optional connector name for KWIN_FORCE_DESKTOP_OUTPUTS
    int sbsWidth = 0; // output width that triggers VR (0 = auto-start on connect)
    int sbsHeight = 0; // output height that triggers VR

    // Service-type fields
    QString detectService; // D-Bus service name, e.g. "org.meumeu.wivrn"

    // VR rendering parameters (all types)
    int width = 0; // per-eye render width
    int height = 0; // per-eye render height
    int refresh = 60;
    float scale = 1.0f;
    QString openxrRuntime; // "monado" or "wivrn"

    bool isValid() const;

    /** True if the given output resolution matches this profile's SBS trigger. */
    bool isSbsMode(int modeWidth, int modeHeight) const;

    /** True for display-type profiles that activate VR on connect (no SBS detection). */
    bool isAutoStart() const
    {
        return detectType == VrDetectType::Display && sbsWidth == 0 && sbsHeight == 0;
    }
};

class VrProfileLoader
{
public:
    static QList<VrProfile> loadProfiles(const QString &dir = QStringLiteral("/etc/vr-profiles.d"));
    static bool isUsbDevicePresent(const QString &usbId);

    /**
     * Reads the EDID monitor name for a KWin output (e.g. "DP-1" → "Air").
     * Scans /sys/class/drm/card*-<outputName>/edid and parses 0xFC descriptors.
     * Returns an empty string if the EDID is unavailable or contains no monitor name.
     */
    static QString readEdidMonitorName(const QString &outputName);
};

} // namespace KWin
