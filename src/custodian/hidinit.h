/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QByteArray>
#include <QObject>
#include <QString>

/**
 * Sends raw HID output reports to a device identified by USB vendor/product IDs
 * and optionally a specific interface number.
 *
 * Device nodes are discovered via /sys/class/hidraw at call time — no state is
 * held between calls, so device reconnects are handled transparently.
 */
class HidInit : public QObject
{
    Q_OBJECT
public:
    explicit HidInit(QObject *parent = nullptr);

    /**
     * Send payload to the first hidraw device matching vendor:product on the
     * given interface. Returns true on success.
     *
     * vendorId  — USB vendor ID, lowercase hex, e.g. "3318"
     * productId — USB product ID, lowercase hex, e.g. "0424"
     * interface — HID interface number; -1 = first matching interface
     * payload   — raw bytes to write as an HID output report
     */
    bool sendCommand(const QString &vendorId,
                     const QString &productId,
                     int interface,
                     const QByteArray &payload);

private:
    /**
     * Walk /sys/class/hidraw to find a node matching the given USB IDs and interface.
     * Returns the /dev/hidrawN path, or an empty string if not found.
     */
    QString findHidrawNode(const QString &vendorId,
                           const QString &productId,
                           int interface) const;
};
