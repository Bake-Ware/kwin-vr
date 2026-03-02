/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "hidinit.h"
#include "custodian_logging.h"

#include <QDir>
#include <QFile>

#include <fcntl.h>
#include <unistd.h>

HidInit::HidInit(QObject *parent)
    : QObject(parent)
{
}

bool HidInit::sendCommand(const QString &vendorId,
                          const QString &productId,
                          int interface,
                          const QByteArray &payload)
{
    if (payload.isEmpty()) {
        qCWarning(KWINVRCUSTODIAN) << "HidInit: empty payload, nothing to send";
        return false;
    }

    const QString devNode = findHidrawNode(vendorId, productId, interface);
    if (devNode.isEmpty()) {
        qCWarning(KWINVRCUSTODIAN) << "HidInit: no hidraw device found for"
                                   << vendorId << ":" << productId
                                   << "interface" << interface;
        return false;
    }

    const int fd = ::open(qPrintable(devNode), O_WRONLY | O_NONBLOCK);
    if (fd < 0) {
        qCWarning(KWINVRCUSTODIAN) << "HidInit: cannot open" << devNode
                                   << "— ensure the device has user-accessible permissions"
                                   << "(udev rule: MODE=\"0666\" or add user to 'input' group)";
        return false;
    }

    const ssize_t written = ::write(fd, payload.constData(), payload.size());
    ::close(fd);

    if (written != static_cast<ssize_t>(payload.size())) {
        qCWarning(KWINVRCUSTODIAN) << "HidInit: short write to" << devNode
                                   << "— wrote" << written << "of" << payload.size() << "bytes";
        return false;
    }

    qCInfo(KWINVRCUSTODIAN) << "HidInit: sent" << written << "bytes to" << devNode;
    return true;
}

QString HidInit::findHidrawNode(const QString &vendorId,
                                const QString &productId,
                                int interface) const
{
    const QDir hidrawDir(QStringLiteral("/sys/class/hidraw"));
    const auto entries = hidrawDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);

    for (const QString &entry : entries) {
        const QString hidrawSys = hidrawDir.filePath(entry);

        // Resolve the canonical sysfs path for this hidraw node's device,
        // then walk upward to find the USB device (idVendor / idProduct).
        QString sysPath = QDir(hidrawSys + QStringLiteral("/device")).canonicalPath();

        QString matchedVid;
        QString matchedPid;
        QString interfacePath;

        for (int depth = 0; depth < 6; ++depth) {
            sysPath = QDir(sysPath + QStringLiteral("/..")).canonicalPath();

            QFile vidFile(sysPath + QStringLiteral("/idVendor"));
            QFile pidFile(sysPath + QStringLiteral("/idProduct"));
            if (!vidFile.open(QIODevice::ReadOnly) || !pidFile.open(QIODevice::ReadOnly))
                continue;

            matchedVid = QString::fromLatin1(vidFile.readAll()).trimmed().toLower();
            matchedPid = QString::fromLatin1(pidFile.readAll()).trimmed().toLower();

            if (matchedVid == vendorId && matchedPid == productId) {
                // VID:PID matches. Record the interface path (one level below USB device).
                if (interface >= 0) {
                    // The HID device sits one directory below the USB device;
                    // bInterfaceNumber lives in that intermediate directory.
                    const QString ifPath = QDir(hidrawSys + QStringLiteral("/device/.."))
                                               .canonicalPath();
                    QFile ifFile(ifPath + QStringLiteral("/bInterfaceNumber"));
                    if (ifFile.open(QIODevice::ReadOnly)) {
                        const int ifNum = QString::fromLatin1(ifFile.readAll())
                                              .trimmed()
                                              .toInt(nullptr, 16);
                        if (ifNum != interface)
                            break; // Wrong interface — skip this hidraw node
                    }
                }
                return QStringLiteral("/dev/") + entry;
            }

            // Stop walking when we reach a USB device that doesn't match —
            // going further up would take us to a hub or root, not our device.
            if (!matchedVid.isEmpty())
                break;
        }
    }

    return {};
}
