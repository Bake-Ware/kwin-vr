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
            if ((value.startsWith(u'"') && value.endsWith(u'"')) ||
                (value.startsWith(u'\'') && value.endsWith(u'\'')))
                value = value.mid(1, value.length() - 2);

            if      (key == u"VR_NAME")               p.name = value;
            else if (key == u"VR_DETECT_USB")          p.usbId = value;
            else if (key == u"VR_DISPLAY_CONNECTOR")   p.connectorName = value;
            else if (key == u"VR_WIDTH")               p.width = value.toInt();
            else if (key == u"VR_HEIGHT")              p.height = value.toInt();
            else if (key == u"VR_REFRESH")             p.refresh = value.toInt();
            else if (key == u"VR_SCALE")               p.scale = value.toFloat();
            else if (key == u"VR_AUTO_START")          p.autoStart = (value.compare(u"true", Qt::CaseInsensitive) == 0);
        }

        if (p.isValid()) {
            profiles.append(p);
            qCInfo(KWINVR) << "Loaded VR profile:" << p.name
                           << "connector:" << p.connectorName
                           << "usb:" << (p.usbId.isEmpty() ? "(any)" : p.usbId)
                           << "autoStart:" << p.autoStart;
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

} // namespace KWin
