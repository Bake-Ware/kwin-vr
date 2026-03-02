/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#pragma once

#include <QObject>
#include <QString>

struct udev;
struct udev_monitor;
class QSocketNotifier;

/**
 * Watches udev events for DRM connector changes and USB device hotplug.
 *
 * Uses a QSocketNotifier on the udev monitor file descriptor — no polling,
 * no threads, no arbitrary sleeps. Events are processed in the Qt event loop
 * as soon as the kernel delivers them.
 */
class UdevMonitor : public QObject
{
    Q_OBJECT
public:
    explicit UdevMonitor(QObject *parent = nullptr);
    ~UdevMonitor() override;

    /**
     * Start monitoring udev events.
     * Returns false if the udev context cannot be created (e.g. udev not running).
     */
    bool start();

Q_SIGNALS:
    /**
     * Emitted when a DRM connector fires a change uevent (HPD, EDID update, mode change).
     * connectorPath is the full sysfs path, e.g. /sys/class/drm/card1-DP-1.
     */
    void drmConnectorChanged(const QString &connectorPath);

    /**
     * Emitted when a USB device is added.
     * vendorId and productId are lowercase hex strings, e.g. "3318", "0424".
     * devNode is the device node path (e.g. /dev/hidraw0); may be empty for interface-level events.
     */
    void usbDeviceAdded(const QString &vendorId, const QString &productId, const QString &devNode);

    /**
     * Emitted when a USB device is removed.
     */
    void usbDeviceRemoved(const QString &vendorId, const QString &productId);

private:
    void processEvent();

    udev *m_udev = nullptr;
    udev_monitor *m_monitor = nullptr;
    QSocketNotifier *m_notifier = nullptr;
};
