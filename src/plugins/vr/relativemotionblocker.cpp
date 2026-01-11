/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "relativemotionblocker.h"

#include "input.h"
#include "input_event.h"
#include "pointer_input.h"

#include <QObject>
#include <QQuickItem>
#include <input.h>

using namespace KWin;

class RelativeBlockFilter : public InputEventFilter
{
public:
    explicit RelativeBlockFilter(InputFilterOrder::Order weight)
        : InputEventFilter(weight) { };
    virtual bool pointerMotion(PointerMotionEvent *event) override
    {
        if (input()->pointer()->isConstrained()) {
            return false;
        } else {
            return !(event->device == m_allowedDevice);
        }
    };

    KWin::InputDevice *m_allowedDevice = nullptr;
};

RelativeMotionBlocker::RelativeMotionBlocker(QObject *parent)
    : QObject{parent}
    , m_filter(new RelativeBlockFilter(InputFilterOrder::PlaceholderOutput))

{
}

RelativeMotionBlocker::~RelativeMotionBlocker()
{
    if (m_filterInstalled) {
        input()->uninstallInputEventFilter(m_filter);
    }
    delete m_filter;
}

KWin::InputDevice *RelativeMotionBlocker::allowedDevice() const
{
    return static_cast<RelativeBlockFilter *>(m_filter)->m_allowedDevice;
}

void RelativeMotionBlocker::setAllowedDevice(KWin::InputDevice *newAllowedDevice)
{
    auto &currentAllowedDevice = static_cast<RelativeBlockFilter *>(m_filter)->m_allowedDevice;

    if (currentAllowedDevice == newAllowedDevice)
        return;

    if (currentAllowedDevice) {
        disconnect(currentAllowedDevice, &QObject::destroyed, this, &RelativeMotionBlocker::resetAllowedDevice);
    }

    currentAllowedDevice = newAllowedDevice;

    if (newAllowedDevice) {
        connect(currentAllowedDevice, &QObject::destroyed, this, &RelativeMotionBlocker::resetAllowedDevice);
    }

    Q_EMIT allowedDeviceChanged();

    QMetaObject::invokeMethod(this, &RelativeMotionBlocker::updateInputFilter, Qt::QueuedConnection);
}

void RelativeMotionBlocker::updateInputFilter()
{
    auto allowedDevice = static_cast<RelativeBlockFilter *>(m_filter)->m_allowedDevice;

    if (allowedDevice) {
        if (!m_filterInstalled) {
            input()->installInputEventFilter(m_filter);
            m_filterInstalled = true;
        }
    } else {
        if (m_filterInstalled) {
            input()->uninstallInputEventFilter(m_filter);
            m_filterInstalled = false;
        }
    }
}

void RelativeMotionBlocker::resetAllowedDevice()
{
    setAllowedDevice(nullptr);
}
