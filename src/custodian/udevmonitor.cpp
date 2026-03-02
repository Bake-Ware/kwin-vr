/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "udevmonitor.h"
#include "custodian_logging.h"

#include <QSocketNotifier>

#include <libudev.h>

UdevMonitor::UdevMonitor(QObject *parent)
    : QObject(parent)
{
}

UdevMonitor::~UdevMonitor()
{
    delete m_notifier;
    m_notifier = nullptr;

    if (m_monitor)
        udev_monitor_unref(m_monitor);
    if (m_udev)
        udev_unref(m_udev);
}

bool UdevMonitor::start()
{
    m_udev = udev_new();
    if (!m_udev) {
        qCWarning(KWINVRCUSTODIAN) << "Failed to create udev context";
        return false;
    }

    m_monitor = udev_monitor_new_from_netlink(m_udev, "udev");
    if (!m_monitor) {
        qCWarning(KWINVRCUSTODIAN) << "Failed to create udev netlink monitor";
        return false;
    }

    // Subscribe to DRM (connector hotplug, EDID/mode changes) and USB/hidraw (device hotplug)
    udev_monitor_filter_add_match_subsystem_devtype(m_monitor, "drm", nullptr);
    udev_monitor_filter_add_match_subsystem_devtype(m_monitor, "usb", "usb_device");
    udev_monitor_filter_add_match_subsystem_devtype(m_monitor, "hidraw", nullptr);

    if (udev_monitor_enable_receiving(m_monitor) < 0) {
        qCWarning(KWINVRCUSTODIAN) << "Failed to enable udev monitor receiving";
        return false;
    }

    const int fd = udev_monitor_get_fd(m_monitor);
    m_notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
    connect(m_notifier, &QSocketNotifier::activated, this, &UdevMonitor::processEvent);

    qCInfo(KWINVRCUSTODIAN) << "udev monitor started (drm + usb_device + hidraw)";
    return true;
}

void UdevMonitor::processEvent()
{
    udev_device *dev = udev_monitor_receive_device(m_monitor);
    if (!dev)
        return;

    const char *subsystem = udev_device_get_subsystem(dev);
    const char *action = udev_device_get_action(dev);

    if (!subsystem || !action) {
        udev_device_unref(dev);
        return;
    }

    const QLatin1String subsys(subsystem);
    const QLatin1String act(action);

    if (subsys == QLatin1String("drm")) {
        if (act == QLatin1String("change")) {
            // Filter to connector-level events only (have CONNECTOR_STATUS property).
            // Card-level events (e.g. GPU mode changes) do not carry this property.
            const char *connStatus = udev_device_get_property_value(dev, "CONNECTOR_STATUS");
            if (connStatus) {
                const char *sysPath = udev_device_get_syspath(dev);
                if (sysPath)
                    Q_EMIT drmConnectorChanged(QString::fromLatin1(sysPath));
            }
        }
    } else if (subsys == QLatin1String("usb") || subsys == QLatin1String("hidraw")) {
        // For hidraw, walk up to the USB device parent to get VID:PID
        udev_device *usbDev = (subsys == QLatin1String("usb"))
            ? udev_device_ref(dev)
            : udev_device_get_parent_with_subsystem_devtype(dev, "usb", "usb_device");

        if (usbDev) {
            const char *vid = udev_device_get_sysattr_value(usbDev, "idVendor");
            const char *pid = udev_device_get_sysattr_value(usbDev, "idProduct");

            if (vid && pid) {
                const QString vendorId = QString::fromLatin1(vid).toLower();
                const QString productId = QString::fromLatin1(pid).toLower();
                const char *devNode = udev_device_get_devnode(dev);
                const QString node = devNode ? QString::fromLatin1(devNode) : QString();

                if (act == QLatin1String("add")) {
                    Q_EMIT usbDeviceAdded(vendorId, productId, node);
                } else if (act == QLatin1String("remove")) {
                    Q_EMIT usbDeviceRemoved(vendorId, productId);
                }
            }

            if (subsys == QLatin1String("usb"))
                udev_device_unref(usbDev);
            // hidraw parent is owned by dev; do not unref separately
        }
    }

    udev_device_unref(dev);
}
