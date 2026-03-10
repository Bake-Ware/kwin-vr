/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "custodianprofile.h"
#include "custodian_logging.h"

#include <QDir>
#include <QFile>
#include <QTextStream>

// ─── CustodianProfile ─────────────────────────────────────────────────────────

bool CustodianProfile::isValid() const
{
    if (name.isEmpty())
        return false;

    switch (trigger) {
    case ProfileTrigger::Edid:
        return (!edidVendor.isEmpty() || !edidName.isEmpty())
            && (sbsWidth > 0 || sbsHeight > 0 || desktopWidth == 0);
    case ProfileTrigger::Service:
        return !serviceName.isEmpty();
    case ProfileTrigger::Manual:
    case ProfileTrigger::Always:
        return true;
    }
    return false;
}

bool CustodianProfile::matchesEdidVendor(const QString &vendor) const
{
    if (edidVendor.isEmpty())
        return false;
    return edidVendor.compare(vendor, Qt::CaseInsensitive) == 0;
}

bool CustodianProfile::matchesEdidName(const QString &monitorName) const
{
    if (edidName.isEmpty())
        return false;
    return monitorName.contains(edidName, Qt::CaseInsensitive);
}

bool CustodianProfile::isSbsMode(int width, int height) const
{
    if (sbsWidth <= 0 || sbsHeight <= 0)
        return false;
    return width == sbsWidth && height == sbsHeight;
}

bool CustodianProfile::isDesktopMode(int width, int height) const
{
    if (desktopWidth > 0 && desktopHeight > 0)
        return width == desktopWidth && height == desktopHeight;
    // No explicit desktop mode — anything that isn't SBS counts
    return !isSbsMode(width, height);
}

QString CustodianProfile::inferredSystemdUnit() const
{
    if (!systemdUnit.isEmpty())
        return systemdUnit;
    if (openxrRuntime == QLatin1String("monado"))
        return QStringLiteral("monado.service");
    if (openxrRuntime == QLatin1String("wivrn"))
        return QStringLiteral("wivrn-server.service");
    return {};
}

// ─── CustodianProfileLoader ───────────────────────────────────────────────────

QList<CustodianProfile> CustodianProfileLoader::loadProfiles(const QString &directory)
{
    QList<CustodianProfile> profiles;
    const QDir dir(directory);
    if (!dir.exists()) {
        qCInfo(KWINVRCUSTODIAN) << "Profile directory does not exist:" << directory;
        return profiles;
    }

    const auto entries = dir.entryList({QStringLiteral("*.conf")}, QDir::Files, QDir::Name);
    for (const QString &entry : entries) {
        QFile file(dir.filePath(entry));
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            qCWarning(KWINVRCUSTODIAN) << "Cannot open profile:" << file.fileName();
            continue;
        }

        QTextStream in(&file);
        CustodianProfile p;

        while (!in.atEnd()) {
            const QString line = in.readLine().trimmed();
            if (line.startsWith(u'#') || !line.contains(u'='))
                continue;

            const int eq = line.indexOf(u'=');
            const QString key = line.left(eq).trimmed();
            QString value = line.mid(eq + 1).trimmed();

            // Strip surrounding quotes
            if (value.size() >= 2
                && ((value.startsWith(u'"') && value.endsWith(u'"'))
                    || (value.startsWith(u'\'') && value.endsWith(u'\'')))) {
                value = value.mid(1, value.length() - 2);
            }

            // Keys shared with the plugin (VR_* prefix)
            if (key == QLatin1String("VR_NAME")) {
                p.name = value;
            } else if (key == QLatin1String("VR_DETECT_TYPE")) {
                const auto v = value.toLower();
                if (v == QLatin1String("service") || v == QLatin1String("remote"))
                    p.trigger = ProfileTrigger::Service;
                else if (v == QLatin1String("manual"))
                    p.trigger = ProfileTrigger::Manual;
                else if (v == QLatin1String("always") || v == QLatin1String("fallback"))
                    p.trigger = ProfileTrigger::Always;
                else // "display", "local", "edid", or anything else
                    p.trigger = ProfileTrigger::Edid;
            } else if (key == QLatin1String("VR_EDID_NAME")) {
                p.edidName = value;
            } else if (key == QLatin1String("VR_DETECT_SERVICE")) {
                p.serviceName = value;
            } else if (key == QLatin1String("VR_SBS_WIDTH")) {
                p.sbsWidth = value.toInt();
            } else if (key == QLatin1String("VR_SBS_HEIGHT")) {
                p.sbsHeight = value.toInt();
            } else if (key == QLatin1String("VR_WIDTH")) {
                p.vrWidth = value.toInt();
            } else if (key == QLatin1String("VR_HEIGHT")) {
                p.vrHeight = value.toInt();
            } else if (key == QLatin1String("VR_REFRESH")) {
                p.vrRefresh = value.toInt();
            } else if (key == QLatin1String("VR_SCALE")) {
                p.vrScale = value.toFloat();
            } else if (key == QLatin1String("VR_OPENXR_RUNTIME")) {
                p.openxrRuntime = value.toLower();
            }
            // Custodian-specific keys
            else if (key == QLatin1String("VR_EDID_VENDOR")) {
                p.edidVendor = value.toUpper();
            } else if (key == QLatin1String("VR_EDID_PRODUCT")) {
                bool ok = false;
                p.edidProductId = static_cast<quint16>(value.toUInt(&ok, 16));
                if (!ok)
                    qCWarning(KWINVRCUSTODIAN) << "Invalid VR_EDID_PRODUCT in" << entry << ":" << value;
            } else if (key == QLatin1String("VR_DESKTOP_WIDTH")) {
                p.desktopWidth = value.toInt();
            } else if (key == QLatin1String("VR_DESKTOP_HEIGHT")) {
                p.desktopHeight = value.toInt();
            } else if (key == QLatin1String("VR_HID_VENDOR")) {
                p.hidVendorId = value.toLower();
            } else if (key == QLatin1String("VR_HID_PRODUCT")) {
                p.hidProductId = value.toLower();
            } else if (key == QLatin1String("VR_HID_INTERFACE")) {
                p.hidInterface = value.toInt();
            } else if (key == QLatin1String("VR_HID_PAYLOAD_2D")) {
                p.hidPayload2D = parseHexPayload(value);
            } else if (key == QLatin1String("VR_HID_PAYLOAD_3D")) {
                p.hidPayload3D = parseHexPayload(value);
            } else if (key == QLatin1String("VR_SYSTEMD_UNIT")) {
                p.systemdUnit = value;
            } else if (key == QLatin1String("VR_VIRTUAL_WIDTH")) {
                p.virtualWidth = value.toInt();
            } else if (key == QLatin1String("VR_VIRTUAL_HEIGHT")) {
                p.virtualHeight = value.toInt();
            } else if (key == QLatin1String("VR_DP_FORCE_RETRAIN")) {
                p.dpForceRetrain = (value == QLatin1String("true") || value == QLatin1String("1"));
            } else if (key == QLatin1String("VR_AUTOSTART")) {
                p.autoStart = (value == QLatin1String("true") || value == QLatin1String("1"));
            } else if (key == QLatin1String("VR_MONADO_ENV")) {
                // Accumulate — multiple VR_MONADO_ENV lines are allowed
                p.monadoEnvVars.append(value);
            }
        }

        if (!p.isValid()) {
            qCWarning(KWINVRCUSTODIAN) << "Skipping invalid or unrecognised profile in:" << entry;
            continue;
        }

        profiles.append(p);
        qCInfo(KWINVRCUSTODIAN) << "Loaded profile:" << p.name
                                << "(trigger:" << static_cast<int>(p.trigger) << ")";
    }

    return profiles;
}

QByteArray CustodianProfileLoader::parseHexPayload(const QString &hex)
{
    QByteArray result;
    const QStringList parts = hex.split(u':', Qt::SkipEmptyParts);
    for (const QString &part : parts) {
        bool ok = false;
        const uint byte = part.trimmed().toUInt(&ok, 16);
        if (!ok || byte > 0xFF) {
            qCWarning(KWINVRCUSTODIAN) << "Invalid hex byte in HID payload:" << part;
            return {};
        }
        result.append(static_cast<char>(byte));
    }
    return result;
}

QByteArray CustodianProfileLoader::readEdid(const QString &connectorSysfsPath)
{
    QFile file(connectorSysfsPath + QStringLiteral("/edid"));
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return file.readAll();
}

bool CustodianProfileLoader::parseEdidVendorProduct(const QByteArray &edid,
                                                    QString &vendorOut,
                                                    quint16 &productIdOut)
{
    if (edid.size() < 12)
        return false;

    // Bytes 8–9: manufacturer ID, big-endian 16-bit.
    // Bits 14–10 = first letter, 9–5 = second, 4–0 = third (1=A … 26=Z).
    const quint16 mfr = (static_cast<quint8>(edid[8]) << 8) | static_cast<quint8>(edid[9]);
    const char c0 = 'A' + static_cast<char>((mfr >> 10) & 0x1F) - 1;
    const char c1 = 'A' + static_cast<char>((mfr >> 5) & 0x1F) - 1;
    const char c2 = 'A' + static_cast<char>(mfr & 0x1F) - 1;

    if (c0 < 'A' || c0 > 'Z' || c1 < 'A' || c1 > 'Z' || c2 < 'A' || c2 > 'Z')
        return false;

    const char vendorChars[3] = {c0, c1, c2};
    vendorOut = QString::fromLatin1(vendorChars, 3);

    // Bytes 10–11: product code, little-endian
    productIdOut = static_cast<quint8>(edid[10]) | (static_cast<quint8>(edid[11]) << 8);

    return true;
}

QString CustodianProfileLoader::parseEdidMonitorName(const QByteArray &edid)
{
    static constexpr int kEdidBlockSize = 128;
    static constexpr int kDescOffsets[] = {54, 72, 90, 108};
    static constexpr quint8 kDescMonitorName = 0xFC;

    if (edid.size() < kEdidBlockSize)
        return {};

    for (int offset : kDescOffsets) {
        if (offset + 18 > edid.size())
            continue;
        // Detailed timing descriptors have non-zero bytes 0–1;
        // monitor/range/name descriptors have bytes 0–1 = 0x00.
        if (static_cast<quint8>(edid[offset]) != 0x00 || static_cast<quint8>(edid[offset + 1]) != 0x00)
            continue;
        if (static_cast<quint8>(edid[offset + 3]) != kDescMonitorName)
            continue;

        const QByteArray raw = edid.mid(offset + 5, 13);
        const int term = raw.indexOf('\n');
        return QString::fromLatin1(term >= 0 ? raw.left(term) : raw).trimmed();
    }

    return {};
}

QString CustodianProfileLoader::readCurrentMode(const QString &connectorSysfsPath)
{
    QFile file(connectorSysfsPath + QStringLiteral("/modes"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return {};
    return QString::fromLatin1(file.readLine()).trimmed();
}

bool CustodianProfileLoader::parseMode(const QString &modeStr, int &widthOut, int &heightOut)
{
    const int x = modeStr.indexOf(u'x');
    if (x < 1)
        return false;
    bool wOk = false, hOk = false;
    widthOut = modeStr.left(x).toInt(&wOk);
    heightOut = modeStr.mid(x + 1).toInt(&hOk);
    return wOk && hOk && widthOut > 0 && heightOut > 0;
}
