/*
    SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include "vrpointeroffset.h"

#include "input.h"
#include "input_event.h"
#include "input_event_spy.h"

#include <algorithm>

using namespace KWin;

class PointerOffsetSpy : public InputEventSpy
{
public:
    void pointerMotion(PointerMotionEvent *event) override
    {
        if (!m_enabled) {
            return;
        }

        // Ignore events from the VR input device
        if (event->device == m_vrDevice) {
            return;
        }

        // Accumulate delta as angular offset
        const float dx = event->delta.x() * m_sensitivity;
        const float dy = event->delta.y() * m_sensitivity;

        const float newX = std::clamp(m_offsetX + dx, -m_maxOffset, m_maxOffset);
        const float newY = std::clamp(m_offsetY - dy, -m_maxOffset, m_maxOffset);

        if (newX != m_offsetX || newY != m_offsetY) {
            m_offsetX = newX;
            m_offsetY = newY;
            if (m_owner) {
                Q_EMIT m_owner->offsetChanged();
            }
        }
    }

    VrPointerOffset *m_owner = nullptr;
    InputDevice *m_vrDevice = nullptr;
    bool m_enabled = false;
    float m_offsetX = 0.0f;
    float m_offsetY = 0.0f;
    float m_sensitivity = 0.1f;
    float m_maxOffset = 20.0f;
};

VrPointerOffset::VrPointerOffset(QObject *parent)
    : QObject(parent)
    , m_spy(new PointerOffsetSpy())
{
    static_cast<PointerOffsetSpy *>(m_spy)->m_owner = this;
}

VrPointerOffset::~VrPointerOffset()
{
    if (m_spyInstalled) {
        input()->uninstallInputEventSpy(m_spy);
    }
    delete m_spy;
}

bool VrPointerOffset::enabled() const
{
    return m_enabled;
}

void VrPointerOffset::setEnabled(bool newEnabled)
{
    if (m_enabled == newEnabled) {
        return;
    }
    m_enabled = newEnabled;
    static_cast<PointerOffsetSpy *>(m_spy)->m_enabled = newEnabled;
    Q_EMIT enabledChanged();
    QMetaObject::invokeMethod(this, &VrPointerOffset::updateSpy, Qt::QueuedConnection);
}

InputDevice *VrPointerOffset::vrDevice() const
{
    return static_cast<PointerOffsetSpy *>(m_spy)->m_vrDevice;
}

void VrPointerOffset::setVrDevice(InputDevice *newVrDevice)
{
    auto spy = static_cast<PointerOffsetSpy *>(m_spy);
    if (spy->m_vrDevice == newVrDevice) {
        return;
    }
    if (spy->m_vrDevice) {
        disconnect(spy->m_vrDevice, &QObject::destroyed, this, &VrPointerOffset::resetVrDevice);
    }
    spy->m_vrDevice = newVrDevice;
    if (newVrDevice) {
        connect(newVrDevice, &QObject::destroyed, this, &VrPointerOffset::resetVrDevice);
    }
    Q_EMIT vrDeviceChanged();
}

float VrPointerOffset::offsetX() const
{
    return static_cast<PointerOffsetSpy *>(m_spy)->m_offsetX;
}

float VrPointerOffset::offsetY() const
{
    return static_cast<PointerOffsetSpy *>(m_spy)->m_offsetY;
}

float VrPointerOffset::sensitivity() const
{
    return m_sensitivity;
}

void VrPointerOffset::setSensitivity(float newSensitivity)
{
    if (qFuzzyCompare(m_sensitivity, newSensitivity)) {
        return;
    }
    m_sensitivity = newSensitivity;
    static_cast<PointerOffsetSpy *>(m_spy)->m_sensitivity = newSensitivity;
    Q_EMIT sensitivityChanged();
}

float VrPointerOffset::maxOffset() const
{
    return m_maxOffset;
}

void VrPointerOffset::setMaxOffset(float newMaxOffset)
{
    if (qFuzzyCompare(m_maxOffset, newMaxOffset)) {
        return;
    }
    m_maxOffset = newMaxOffset;
    static_cast<PointerOffsetSpy *>(m_spy)->m_maxOffset = newMaxOffset;
    Q_EMIT maxOffsetChanged();
}

void VrPointerOffset::reset()
{
    auto spy = static_cast<PointerOffsetSpy *>(m_spy);
    if (spy->m_offsetX != 0.0f || spy->m_offsetY != 0.0f) {
        spy->m_offsetX = 0.0f;
        spy->m_offsetY = 0.0f;
        Q_EMIT offsetChanged();
    }
}

void VrPointerOffset::updateSpy()
{
    if (m_enabled) {
        if (!m_spyInstalled) {
            input()->installInputEventSpy(m_spy);
            m_spyInstalled = true;
        }
    } else {
        if (m_spyInstalled) {
            input()->uninstallInputEventSpy(m_spy);
            m_spyInstalled = false;
        }
    }
}

void VrPointerOffset::resetVrDevice()
{
    setVrDevice(nullptr);
}
