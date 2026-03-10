/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QByteArray>
#include <QList>
#include <QString>
#include <QStringList>

/**
 * How a custodian profile is triggered.
 *
 * Edid:    The connector EDID matches vendor/name, and the display enters the SBS mode.
 *          Config alias: VR_DETECT_TYPE=display, VR_DETECT_TYPE=local
 * Service: A named D-Bus service appears on the session bus (e.g. WiVRn).
 *          Config alias: VR_DETECT_TYPE=service, VR_DETECT_TYPE=remote
 * Manual:  The user initiates VR from the settings UI — no automatic trigger.
 *          Config alias: VR_DETECT_TYPE=manual
 * Always:  Fallback — always available. Not auto-started unless VR_AUTOSTART=true.
 *          Config alias: VR_DETECT_TYPE=always, VR_DETECT_TYPE=fallback
 */
enum class ProfileTrigger {
    Edid,
    Service,
    Manual,
    Always,
};

/**
 * VR headset profile as understood by the custodian.
 *
 * Loaded from /etc/vr-profiles.d/ (*.conf files). The custodian reads all
 * VR_* keys that the plugin reads, plus additional keys for hardware init
 * and EDID vendor matching. Unknown keys are silently ignored.
 */
struct CustodianProfile
{
    QString name;
    ProfileTrigger trigger = ProfileTrigger::Edid;

    // ── EDID matching (trigger = Edid) ────────────────────────────────────
    // Either vendor code or name must be set for the profile to match.
    QString edidVendor; // 3-letter EDID manufacturer code, e.g. "XRL"
    quint16 edidProductId = 0; // EDID product code; 0 = any product
    QString edidName; // EDID monitor name substring, e.g. "Air"

    // Display mode that signals VR-on; 0x0 = activate on connect (e.g. tethered HMD)
    int sbsWidth = 0;
    int sbsHeight = 0;

    // Display mode that signals VR-off; 0x0 = any mode that isn't SBS
    int desktopWidth = 0;
    int desktopHeight = 0;

    // ── Service matching (trigger = Service) ──────────────────────────────
    QString serviceName; // D-Bus service name, e.g. "net.wivrn.Server"

    // ── HID initialisation ────────────────────────────────────────────────
    // Sent once when the matching USB device is detected, before VR activates.
    QString hidVendorId; // USB vendor ID in hex lowercase, e.g. "3318"
    QString hidProductId; // USB product ID in hex lowercase, e.g. "0424"
    int hidInterface = -1; // HID interface number; -1 = first matching interface
    QByteArray hidPayload2D; // Bytes to send to switch device to 2D mode
    QByteArray hidPayload3D; // Bytes to send to switch device to 3D/SBS mode

    // ── OpenXR runtime ────────────────────────────────────────────────────
    QString openxrRuntime; // "monado" | "wivrn" | "none"
    QString systemdUnit; // Override the inferred systemd unit name

    // ── Display / virtual output parameters (forwarded to plugin) ─────────
    int vrWidth = 0;
    int vrHeight = 0;
    int vrRefresh = 60;
    float vrScale = 1.0f;
    int virtualWidth = 0;
    int virtualHeight = 0;

    bool dpForceRetrain = false;

    // Whether to auto-activate VR mode when this profile matches.
    // Default true for local/remote, false for fallback.
    bool autoStart = true;

    // Extra environment variables to pass to Monado for this profile.
    // Parsed from VR_MONADO_ENV, format: "KEY=VALUE" (one pair per field).
    QStringList monadoEnvVars;

    bool isValid() const;

    /** True if the given EDID vendor code matches this profile. */
    bool matchesEdidVendor(const QString &vendor) const;

    /** True if the given EDID monitor name substring matches this profile. */
    bool matchesEdidName(const QString &monitorName) const;

    /** True if the given output resolution matches this profile's SBS trigger. */
    bool isSbsMode(int width, int height) const;

    /** True if the given output resolution matches this profile's desktop (VR-off) mode. */
    bool isDesktopMode(int width, int height) const;

    /**
     * Returns the systemd unit to start/stop for this profile's OpenXR runtime.
     * Uses systemdUnit if set; otherwise infers from openxrRuntime.
     */
    QString inferredSystemdUnit() const;
};

class CustodianProfileLoader
{
public:
    static QList<CustodianProfile> loadProfiles(
        const QString &directory = QStringLiteral("/etc/vr-profiles.d"));

    // Parse a colon-delimited hex string into raw bytes: "01:00:aa:bb" → QByteArray
    static QByteArray parseHexPayload(const QString &hex);

    // Read raw EDID binary from a DRM connector sysfs path
    static QByteArray readEdid(const QString &connectorSysfsPath);

    /**
     * Parse EDID manufacturer vendor code and product ID.
     * Returns false if the EDID is malformed or too short.
     */
    static bool parseEdidVendorProduct(const QByteArray &edid,
                                       QString &vendorOut,
                                       quint16 &productIdOut);

    /**
     * Parse the monitor name from EDID descriptor type 0xFC.
     * Returns an empty string if not present.
     */
    static QString parseEdidMonitorName(const QByteArray &edid);

    // Read the first line of the DRM modes file (= current preferred mode), e.g. "1920x1080"
    static QString readCurrentMode(const QString &connectorSysfsPath);

    // Parse "WxH" into width and height components; returns false on failure
    static bool parseMode(const QString &modeStr, int &widthOut, int &heightOut);
};
