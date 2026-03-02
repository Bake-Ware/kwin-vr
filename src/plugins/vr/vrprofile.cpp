/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "vrprofile.h"

#include <QDir>
#include <QFile>
#include <QTextStream>

#include "kwinvr_logging.h"

namespace KWin
{

bool VrProfile::isValid() const
{
    if (name.isEmpty())
        return false;
    switch (detectType) {
    case VrDetectType::Display:
        return !edidName.isEmpty() && width > 0 && height > 0;
    case VrDetectType::Service:
        return !detectService.isEmpty() && width > 0 && height > 0;
    }
    return false;
}

bool VrProfile::isSbsMode(int modeWidth, int modeHeight) const
{
    if (detectType != VrDetectType::Display || sbsWidth == 0 || sbsHeight == 0)
        return false;
    return modeWidth == sbsWidth && modeHeight == sbsHeight;
}

QList<VrProfile> VrProfileLoader::loadProfiles(const QString &dir)
{
    QList<VrProfile> profiles;
    QDir d(dir);
    if (!d.exists()) {
        qCWarning(KWINVR) << "VR profile directory not found:" << dir;
        return profiles;
    }

    const auto entries = d.entryList({QStringLiteral("*.conf")}, QDir::Files, QDir::Name);
    for (const auto &entry : entries) {
        QFile f(d.filePath(entry));
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            qCWarning(KWINVR) << "Cannot open VR profile:" << f.fileName();
            continue;
        }

        QTextStream in(&f);
        VrProfile p;

        while (!in.atEnd()) {
            QString line = in.readLine().trimmed();
            if (line.startsWith(u'#') || !line.contains(u'='))
                continue;

            const int eq = line.indexOf(u'=');
            const QString key = line.left(eq).trimmed();
            QString value = line.mid(eq + 1).trimmed();

            // Strip surrounding quotes
            if (value.size() >= 2
                && ((value.startsWith(u'"') && value.endsWith(u'"'))
                    || (value.startsWith(u'\'') && value.endsWith(u'\''))))
                value = value.mid(1, value.length() - 2);

            if (key == u"VR_NAME") {
                p.name = value;
            } else if (key == u"VR_DETECT_TYPE") {
                if (value.compare(u"service", Qt::CaseInsensitive) == 0)
                    p.detectType = VrDetectType::Service;
                else
                    p.detectType = VrDetectType::Display;
            } else if (key == u"VR_EDID_NAME") {
                p.edidName = value;
            } else if (key == u"VR_DETECT_USB") {
                p.usbId = value;
            } else if (key == u"VR_CONNECTOR_HINT") {
                p.connectorHint = value;
            } else if (key == u"VR_SBS_WIDTH") {
                p.sbsWidth = value.toInt();
            } else if (key == u"VR_SBS_HEIGHT") {
                p.sbsHeight = value.toInt();
            } else if (key == u"VR_DETECT_SERVICE") {
                p.detectService = value;
            } else if (key == u"VR_WIDTH") {
                p.width = value.toInt();
            } else if (key == u"VR_HEIGHT") {
                p.height = value.toInt();
            } else if (key == u"VR_REFRESH") {
                p.refresh = value.toInt();
            } else if (key == u"VR_SCALE") {
                p.scale = value.toFloat();
            } else if (key == u"VR_OPENXR_RUNTIME") {
                p.openxrRuntime = value;
            }
        }

        if (p.isValid()) {
            profiles.append(p);
            if (p.detectType == VrDetectType::Display) {
                qCInfo(KWINVR) << "Loaded VR profile:" << p.name
                               << "edid:" << p.edidName
                               << "usb:" << (p.usbId.isEmpty() ? QStringLiteral("(any)") : p.usbId)
                               << (p.isAutoStart() ? QStringLiteral("auto-start") : QStringLiteral("sbs-triggered"));
            } else {
                qCInfo(KWINVR) << "Loaded VR profile:" << p.name
                               << "service:" << p.detectService;
            }
        } else {
            qCWarning(KWINVR) << "Skipping invalid VR profile in" << entry;
        }
    }

    return profiles;
}

bool VrProfileLoader::isUsbDevicePresent(const QString &usbId)
{
    if (usbId.isEmpty())
        return true; // no check requested

    const QStringList parts = usbId.split(u':');
    if (parts.size() != 2) {
        qCWarning(KWINVR) << "Invalid USB ID format (expected VID:PID):" << usbId;
        return false;
    }

    const QString vendorId = parts[0].toLower();
    const QString productId = parts[1].toLower();

    const QDir usbDir(QStringLiteral("/sys/bus/usb/devices"));
    const auto devices = usbDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);

    for (const auto &device : devices) {
        const QString path = usbDir.filePath(device);

        QFile vendorFile(path + QStringLiteral("/idVendor"));
        QFile productFile(path + QStringLiteral("/idProduct"));

        if (!vendorFile.open(QIODevice::ReadOnly) || !productFile.open(QIODevice::ReadOnly))
            continue;

        const QString vid = QString::fromLatin1(vendorFile.readAll()).trimmed().toLower();
        const QString pid = QString::fromLatin1(productFile.readAll()).trimmed().toLower();

        if (vid == vendorId && pid == productId)
            return true;
    }

    return false;
}

QString VrProfileLoader::readEdidMonitorName(const QString &outputName)
{
    // EDID base block: 128 bytes.
    // Bytes 54, 72, 90, 108: 18-byte descriptor blocks.
    // Tag 0xFC at descriptor byte 3 → monitor name in bytes 5–17,
    // ASCII, padded with 0x0A (newline) then spaces.
    static const int EDID_BLOCK_SIZE = 128;
    static const int DESC_OFFSETS[] = {54, 72, 90, 108};
    static const quint8 DESC_MONITOR_NAME = 0xFC;

    // Scan all DRM card-connector sysfs entries for a matching output name.
    // e.g. outputName = "DP-1" matches "card1-DP-1".
    const QString suffix = u'-' + outputName;
    QDir sysdrm(QStringLiteral("/sys/class/drm"));
    const auto entries = sysdrm.entryList(QDir::Dirs | QDir::NoDotAndDotDot);

    for (const auto &entry : entries) {
        if (!entry.endsWith(suffix))
            continue;

        QFile edidFile(sysdrm.filePath(entry) + QStringLiteral("/edid"));
        if (!edidFile.open(QIODevice::ReadOnly))
            continue;

        const QByteArray edid = edidFile.readAll();
        if (edid.size() < EDID_BLOCK_SIZE)
            continue;

        for (int offset : DESC_OFFSETS) {
            if (offset + 18 > edid.size())
                continue;

            // Detailed timing descriptors have non-zero bytes 0-1;
            // monitor/range/name descriptors have bytes 0-1 = 0x00.
            if ((quint8)edid[offset] != 0x00 || (quint8)edid[offset + 1] != 0x00)
                continue;

            if ((quint8)edid[offset + 3] != DESC_MONITOR_NAME)
                continue;

            // Bytes 5–17: ASCII name, terminated by 0x0A
            const QByteArray raw = edid.mid(offset + 5, 13);
            const int term = raw.indexOf('\n');
            const QByteArray name = (term >= 0) ? raw.left(term) : raw;
            return QString::fromLatin1(name).trimmed();
        }
    }

    return QString();
}

} // namespace KWin
